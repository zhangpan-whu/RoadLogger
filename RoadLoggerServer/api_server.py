# api_server.py
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
import shutil
import os
import json

#修改：导入 streamlit_analysis_app 中的分析函数
from streamlit_analysis_app import extract_frames, process_sensor_data, generate_scene_tree

app = FastAPI()

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.post("/upload")
async def upload_files(video: UploadFile = File(...), sensor: UploadFile = File(...)):
    # 1. 保存视频文件
    video_path = os.path.join(UPLOAD_DIR, "latest_video.mov")
    with open(video_path, "wb") as buffer:
        shutil.copyfileobj(video.file, buffer)
        
    # 2. 保存传感器数据
    sensor_path = os.path.join(UPLOAD_DIR, "latest_sensor.csv")
    with open(sensor_path, "wb") as buffer:
        shutil.copyfileobj(sensor.file, buffer)
        
    # 修改：3. 自动触发分析逻辑
    try:
        # 抽帧与处理传感器数据
        frames, duration = extract_frames(video_path)
        sensor_summary = process_sensor_data(sensor_path, duration)
        
        # 默认的 Prompt 模板
        default_prompt = """
        请生成如下结构的 JSON：
        {
            "score": 85,
            "summary": "城市道路正常行驶，无异常驾驶行为",
            "details": "车辆在城市道路上平稳行驶，加速度变化平缓，未检测到急刹车或急加速行为。"
        }
        """
        
        # 调用大模型
        result_json_str = generate_scene_tree(frames, sensor_summary, default_prompt, voice_text='')
        
        # 清理并解析 JSON
        clean_json = result_json_str.replace("```json", "").replace("```", "").strip()
        result_dict = json.loads(clean_json)
        
        # 保存结果到本地 (供 Streamlit 界面查看)
        result_file_path = os.path.join(UPLOAD_DIR, "latest_result.json")
        with open(result_file_path, 'w', encoding='utf-8') as f:
            json.dump(result_dict, f, ensure_ascii=False, indent=2)
            
        # 4. 将结果直接返回给 APP
        return JSONResponse(content={
            "status": "success",
            "message": "Analysis completed",
            "data": result_dict
        })

    except Exception as e:
        return JSONResponse(status_code=500, content={
            "status": "error",
            "message": f"Analysis failed: {str(e)}"
        })
        
if __name__ == "__main__":
    import uvicorn
    # 监听 0.0.0.0 让外网可以访问，端口 8000
    uvicorn.run(app, host="0.0.0.0", port=8000)
