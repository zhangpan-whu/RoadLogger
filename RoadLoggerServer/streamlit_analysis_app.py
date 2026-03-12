import streamlit as st
import pandas as pd
import cv2
import base64
import tempfile
import os
import json
import time
import numpy as np
from openai import OpenAI
import requests 

# ================= 配置区域 =================
# 适配云端部署路径
UPLOAD_DIR = "uploads"  # 与 api_server.py 定义的目录保持一致
VIDEO_FILENAME = "latest_video.mov"
SENSOR_FILENAME = "latest_sensor.csv"

# API 配置 (保持原样)
API_KEY = "sk-0b6204172170419f82443c4432c98912" 
BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1" 
MODEL_NAME = "qwen-vl-max" 

# 阿里云语音识别API配置
ASR_API_URL = "https://nls-gateway.cn-shanghai.aliyuncs.com/stream/v1/asr"
ASR_APP_KEY = "your_asr_app_key"

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# ================= 辅助函数 (保持原定义不变) =================

def extract_frames(video_path, num_frames=40):
    """从视频中均匀提取N帧，并转为Base64编码"""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"无法打开视频文件: {video_path}")
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    
    # 增加鲁棒性：防止除以零或空视频
    if fps == 0 or total_frames == 0:
        cap.release()
        return [], 0

    duration = total_frames / fps

    frame_indices = np.linspace(0, total_frames - 1, num_frames, dtype=int)
    base64_frames = []

    for idx in frame_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if ret:
            # 压缩图片以适应Token限制
            _, buffer = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 50])
            base64_frames.append(base64.b64encode(buffer).decode('utf-8'))

    cap.release()
    return base64_frames, duration


def process_sensor_data(csv_file, duration_sec):
    """读取并统计传感器数据的特征"""
    try:
        df = pd.read_csv(csv_file)
    except Exception as e:
        st.error(f"CSV 读取失败: {e}")
        return {}

    # 假设数据列名精确匹配（可能有空格或大小写差异，建议先 df.columns 查看）
    # 增加部分容错处理，去除列名首尾空格
    df.columns = [c.strip() for c in df.columns]
    
    # 映射标准列名以适应不同APP的输出
    col_map = {
        'AccelerationX': 'AccelerationX', 'acc_x': 'AccelerationX',
        'AccelerationY': 'AccelerationY', 'acc_y': 'AccelerationY',
        'GyroZ': 'GyroZ', 'gyro_z': 'GyroZ',
        'speed': 'speed', 'Speed': 'speed'
    }
    # 简单的列名标准化逻辑
    for col in df.columns:
        if col in col_map:
            continue # 已经是标准名
        # 这里可以添加更复杂的映射逻辑

    summary = {
        # 加速度 - 纵向（通常 X，前后）
        "acc_x_max": float(df['AccelerationX'].max()) if 'AccelerationX' in df else 0.0,
        "acc_x_min": float(df['AccelerationX'].min()) if 'AccelerationX' in df else 0.0,
        "acc_x_avg": float(df['AccelerationX'].mean()) if 'AccelerationX' in df else 0.0,
        "acc_x_std": float(df['AccelerationX'].std()) if 'AccelerationX' in df else 0.0,

        # 加速度 - 横向（通常 Y，左右）
        "acc_y_max": float(df['AccelerationY'].max()) if 'AccelerationY' in df else 0.0,
        "acc_y_min": float(df['AccelerationY'].min()) if 'AccelerationY' in df else 0.0,
        "acc_y_std": float(df['AccelerationY'].std()) if 'AccelerationY' in df else 0.0,

        # 陀螺仪 - 偏航角速度
        "gyro_z_max": float(df['GyroZ'].max()) if 'GyroZ' in df else 0.0,
        "gyro_z_min": float(df['GyroZ'].min()) if 'GyroZ' in df else 0.0,
        "gyro_z_abs_max": float(df['GyroZ'].abs().max()) if 'GyroZ' in df else 0.0,
        "gyro_z_std": float(df['GyroZ'].std()) if 'GyroZ' in df else 0.0,

        # 速度
        "speed_max": float(df['speed'].max()) if 'speed' in df else 0.0,
        "speed_avg": float(df['speed'].mean()) if 'speed' in df else 0.0,
        "speed_min": float(df['speed'].min()) if 'speed' in df else 0.0,

        "num_samples": len(df)
    }
    return summary

def speech_to_text(audio_path):
    """使用阿里云ASR将语音转为文字"""
    with open(audio_path, 'rb') as f:
        audio_data = f.read()
    headers = {
        "Authorization": f"Bearer {API_KEY}", 
        "Content-Type": "application/octet-stream"
    }
    params = {
        "appkey": ASR_APP_KEY,
        "format": "wav", 
        "sample_rate": 16000 
    }
    try:
        response = requests.post(ASR_API_URL, headers=headers, params=params, data=audio_data)
        response.raise_for_status()
        result = response.json()
        return result.get('result', '') 
    except Exception as e:
        return f"语音识别失败: {str(e)}"

def generate_scene_tree(video_frames, sensor_summary, custom_prompt, voice_text=''):
    """调用大模型生成场景树 (保持原Prompt逻辑)"""
    messages = [
        {
            "role": "system",
            "content": "你是一个自动驾驶场景理解专家。请根据提供的视频帧、传感器数据、语音描述和文字要求，推断驾驶场景（如城市道路、高速）、行为（如变道、绕行、急刹基于轨迹变化和加速度），并输出自定义JSON格式的场景功能树。"
        },
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": f"""
                    分析任务：
                    1. 传感器数据摘要：
                       - 纵向加速度X范围: {sensor_summary.get('acc_x_min', 0):.2f} ~ {sensor_summary.get('acc_x_max', 0):.2f} (单位 g)
                       (平均: {sensor_summary.get('acc_x_avg', 0):.2f}, 标准差: {sensor_summary.get('acc_x_std', 0):.2f})
                       - 横向加速度 (Y) 波动: 标准差 {sensor_summary.get('acc_y_std', 0):.2f} g （值越大越可能变道/侧向运动）
                       - 偏航角速度 (GyroZ) 峰值: ±{sensor_summary.get('gyro_z_abs_max', 0):.2f} °/s
                       (标准差: {sensor_summary.get('gyro_z_std', 0):.2f}，值大说明转弯/变道明显)
                       - 速度范围: {sensor_summary.get('speed_min', 0):.2f} ~ {sensor_summary.get('speed_max', 0):.2f} km/h (平均 {sensor_summary.get('speed_avg', 0):.2f})
                    
                    2. 司机语音描述：
                    {voice_text}
                    
                    3. 重要提醒：视频是一个非常短的片段（小于30秒），请特别关注车辆的横向移动、车道线跨越、转向灯或轨迹明显变化，判断是否在变道、绕行或其他机动行为，而不是简单直行。
                    
                    4. 快速判断参考规则：
                        - 变道 / 绕行：acc_y_std > 0.15~0.25 g 且 gyro_z_abs_max > 8~15 °/s
                        - 急刹车：acc_x_min < -0.4 g
                        - 急加速：acc_x_max > 0.4 g
                    
                    5. 用户自定义要求：
                    {custom_prompt}

                    6. 输出要求：
                    请直接返回 JSON 格式，不要包含 Markdown 标记。
                    """
                }
            ]
        }
    ]
    for b64_frame in video_frames:
        messages[1]["content"].append({
            "type": "image_url",
            "image_url": {
                "url": f"data:image/jpeg;base64,{b64_frame}"
            }
        })

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=messages,
            temperature=0.1,
            max_tokens=1000
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error calling model: {str(e)}"

if __name__ == "__main__":
    # ================= 界面逻辑 (Streamlit) =================
    st.set_page_config(page_title="RoadLogger Cloud Analysis", layout="wide", page_icon="☁️")

    # 侧边栏：模拟阿里云控制台风格的简单状态栏
    with st.sidebar:
        st.title("☁️ 云端控制台")
        st.markdown("---")
        st.markdown("**服务状态**")
        st.success("API 服务: 运行中")
        st.info("存储服务: 本地挂载")
        
        st.markdown("---")
        st.markdown("**数据源监控**")
        
        # 自动检测文件是否存在
        video_full_path = os.path.join(UPLOAD_DIR, VIDEO_FILENAME)
        csv_full_path = os.path.join(UPLOAD_DIR, SENSOR_FILENAME)
        
        video_exists = os.path.exists(video_full_path)
        csv_exists = os.path.exists(csv_full_path)
        
        if video_exists:
            st.caption(f"✅ 视频已就绪 ({VIDEO_FILENAME})")
            # 显示文件修改时间
            mtime = os.path.getmtime(video_full_path)
            st.caption(f"更新于: {time.ctime(mtime)}")
        else:
            st.caption("❌ 等待 APP 上传视频...")
            
        if csv_exists:
            st.caption(f"✅ 数据已就绪 ({SENSOR_FILENAME})")
        else:
            st.caption("❌ 等待 APP 上传数据...")
            
        if st.button("🔄 刷新文件状态"):
            st.rerun()

    # 主界面
    st.title("🚗 RoadLogger 驾驶行为云端测评")
    st.markdown("基于 **阿里云通义大模型** 与 **RoadLogger APP** 数据的自动驾驶场景分析系统。")

    col1, col2 = st.columns([1, 1])

    with col1:
        st.header("1. 数据源确认")
        
        # 逻辑修改：不再请求上传，而是显示服务器文件
        if video_exists and csv_exists:
            st.success("云端已接收到最新驾驶数据，可以开始分析。")
            st.video(video_full_path)
            
            # 简单预览 CSV
            try:
                preview_df = pd.read_csv(csv_full_path)
                st.dataframe(preview_df.head(3), height=100)
            except:
                st.warning("CSV 文件格式预览失败")
                
        else:
            st.warning("⚠️ 未检测到完整数据。请在 RoadLogger APP 中点击上传。")
            st.info(f"正在监听目录: `{os.path.abspath(UPLOAD_DIR)}`")

        # 语音依然保留手动上传，因为APP端暂未实现语音上传
        st.subheader("补充音频 (可选)")
        uploaded_audio = st.file_uploader("上传司机语音 (MP3/WAV)", type=["mp3", "wav"])

        st.header("2. 定义场景树结构")
        default_prompt = """
        请生成如下结构的 JSON：
        {
            "score": 85,
            "summary": "城市道路正常行驶，无异常驾驶行为",
            "details": "车辆在城市道路上平稳行驶，加速度变化平缓，未检测到急刹车或急加速行为。"
        }
        """
        custom_prompt = st.text_area("Prompt 模板", value=default_prompt, height=200)

        # 只有文件存在时才允许点击
        start_btn = st.button("🚀 开始 AI 分析", type="primary", disabled=not(video_exists and csv_exists))

    with col2:
        st.header("3. 分析结果")

        if start_btn:
            with st.spinner("正在调用通义千问 VL 进行多模态分析..."):
                # 1. 抽帧 (直接读取服务器文件，无需 tempfile)
                frames, duration = extract_frames(video_full_path)
                if frames:
                    st.image(base64.b64decode(frames[0]), caption="关键帧采样预览", use_column_width=True)
                
                # 2. 处理 CSV (直接读取服务器文件)
                sensor_summary = process_sensor_data(csv_full_path, duration)
                with st.expander("查看传感器统计摘要"):
                    st.json(sensor_summary)

                # 3. 处理语音 (如果用户手动上传了)
                voice_text = ''
                if uploaded_audio:
                    # 语音还是需要临时文件，因为是内存上传的
                    afile = tempfile.NamedTemporaryFile(delete=False, suffix='.wav')
                    afile.write(uploaded_audio.read())
                    afile.close()
                    voice_text = speech_to_text(afile.name)
                    st.info(f"语音转文字: {voice_text}")
                    os.remove(afile.name)

                # 4. 调用大模型
                result_json_str = generate_scene_tree(frames, sensor_summary, custom_prompt, voice_text)

                # 5. 展示结果
                try:
                    clean_json = result_json_str.replace("```json", "").replace("```", "").strip()
                    result_dict = json.loads(clean_json)
                    st.success("分析完成！")
                    st.json(result_dict)
                    
                    # 保存分析结果到文件
                    result_file_path = os.path.join(UPLOAD_DIR, "latest_result.json")
                    with open(result_file_path, 'w', encoding='utf-8') as f:
                        json.dump(result_dict, f, ensure_ascii=False, indent=2)
                    st.success(f"分析结果已保存至: {result_file_path}")
                    
                except:
                    st.warning("模型返回非标准 JSON，显示原始文本：")
                    st.text(result_json_str)

    # 页脚：致敬阿里云帮助中心风格
    st.markdown("---")
    st.markdown(
        """
        <div style='text-align: center; color: #666; font-size: 12px;'>
        RoadLogger Cloud Analysis | Powered by Alibaba Cloud ECS & Tongyi Qianwen <br>
        安全合规 | 稳定可靠 | 沪ICP备XXXXXXXX号
        </div>
        """,
        unsafe_allow_html=True
    )
