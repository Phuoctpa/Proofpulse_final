from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from typing import List
import pandas as pd
import joblib
import shutil
import os
import zipfile
import tempfile

from app.gpx_processor import extract_features_from_gpx

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # mở CORS khi dev
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory="app/static"), name="static")

@app.get("/")
def read_root():
    return FileResponse("app/static/index.html")

# === Cấu hình ===
MODEL_PATH = "app/fraud_detector_model.pkl"
UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

model = joblib.load(MODEL_PATH)

# ==== API UPLOAD 1 FILE GPX ====
@app.post("/upload-workout")
async def upload_gpx(
    file: UploadFile = File(...),
    user_address: str = Form(...)
):
    file_path = os.path.join(UPLOAD_DIR, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    features = extract_features_from_gpx(file_path)
    if not features:
        return JSONResponse({"error": "Invalid GPX data"}, status_code=400)

    # Loại bỏ activity_timestamp khi predict
    features_for_model = {k: v for k, v in features.items() if k != 'activity_timestamp'}
    df = pd.DataFrame([features_for_model])
    label = model.predict(df)[0]

    return {
        "result": "REAL" if label == 1 else "FAKE",
        "features": features,  # vẫn trả đủ cho frontend
        "tx_hash": None
    }

# ==== API UPLOAD NHIỀU FILE GPX ====
@app.post("/upload-multiple")
async def upload_multiple_gpx(
    files: List[UploadFile] = File(...),
    user_address: str = Form(...)
):
    results = []
    for file in files:
        file_path = os.path.join(UPLOAD_DIR, file.filename)
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        features = extract_features_from_gpx(file_path)
        if not features:
            results.append({
                "file": file.filename,
                "result": "ERROR",
                "reason": "Invalid GPX data"
            })
            continue

        features_for_model = {k: v for k, v in features.items() if k != 'activity_timestamp'}
        df = pd.DataFrame([features_for_model])
        label = model.predict(df)[0]

        results.append({
            "file": file.filename,
            "result": "REAL" if label == 1 else "FAKE",
            "features": features,
            "tx_hash": None
        })

    return {"results": results}

# ==== API UPLOAD FILE ZIP GPX ====
@app.post("/upload-zip")
async def upload_zip(
    file: UploadFile = File(...),
    user_address: str = Form(...)
):
    zip_path = os.path.join(UPLOAD_DIR, file.filename)
    with open(zip_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    results = []
    with tempfile.TemporaryDirectory() as extract_dir:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)

        for root, _, files in os.walk(extract_dir):
            for name in files:
                if not name.endswith(".gpx"):
                    continue
                file_path = os.path.join(root, name)
                features = extract_features_from_gpx(file_path)
                if not features:
                    results.append({
                        "file": name,
                        "result": "ERROR",
                        "reason": "Invalid GPX data"
                    })
                    continue

                features_for_model = {k: v for k, v in features.items() if k != 'activity_timestamp'}
                df = pd.DataFrame([features_for_model])
                label = model.predict(df)[0]

                results.append({
                    "file": name,
                    "result": "REAL" if label == 1 else "FAKE",
                    "features": features,
                    "tx_hash": None
                })

    return {"results": results}
