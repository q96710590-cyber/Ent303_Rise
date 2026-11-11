# 官方模型

文件：pose_landmarker_lite.task

来源：https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task

SHA-256：59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a

2026-10-24 实际下载、Tasks 加载与本地摄像头推理成功。此哈希记录本次取得的文件，不表示额外的签名验证。

重新获取：`.venv\Scripts\python.exe scripts\download_model.py`。脚本先尝试系统网络，失败后仅在本进程尝试直连，不改系统代理。每次均检查真实模型加载，临时文件在验证进程退出后替换，避免 Windows 文件锁。
