"""Saver backend: يحوّل رابط صفحة (مثل TikTok) إلى ملف فيديو يحمّله الآيفون.

التشغيل: run.bat (على Windows) أو:
    uvicorn main:app --host 0.0.0.0 --port 8000
"""
import time
import uuid
from pathlib import Path

import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

# مجلد الفيديوهات المؤقتة بجانب هذا الملف
DOWNLOADS = (Path(__file__).parent / "downloads").resolve()
DOWNLOADS.mkdir(exist_ok=True)
KEEP_SECONDS = 60 * 60  # نحذف الملفات بعد ساعة

MEDIA_TYPES = {".mp4": "video/mp4", ".m4v": "video/mp4", ".mov": "video/quicktime"}

app = FastAPI(title="Saver backend")


class ResolveRequest(BaseModel):
    url: str


class ResolveResponse(BaseModel):
    video_url: str
    title: str


def delete_old_files() -> None:
    """يحذف الفيديوهات القديمة حتى لا يمتلئ القرص."""
    now = time.time()
    for path in DOWNLOADS.iterdir():
        if path.is_file() and now - path.stat().st_mtime > KEEP_SECONDS:
            path.unlink(missing_ok=True)


@app.get("/health")
def health():
    """لزر Test Connection في التطبيق."""
    return {"status": "ok", "yt_dlp": yt_dlp.version.__version__}


# def (وليس async def): FastAPI يشغّلها في thread منفصل لأن yt-dlp بطيء ويوقف التنفيذ
@app.post("/resolve", response_model=ResolveResponse)
def resolve(body: ResolveRequest, request: Request):
    delete_old_files()
    file_id = uuid.uuid4().hex
    options = {
        # ملف mp4 واحد جاهز: لا يحتاج ffmpeg للدمج، والصور في iOS تقبله
        "format": "best[ext=mp4]/best",
        "outtmpl": str(DOWNLOADS / f"{file_id}.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "max_filesize": 1024 * 1024 * 1024,  # 1 GB حد أعلى
    }
    try:
        with yt_dlp.YoutubeDL(options) as ydl:
            info = ydl.extract_info(body.url, download=True)
            path = Path(ydl.prepare_filename(info))
    except yt_dlp.utils.DownloadError as error:
        # 422 = الطلب مفهوم لكن لا يمكن تنفيذه (رابط غير مدعوم، خاص، ...)
        raise HTTPException(status_code=422, detail=str(error).replace("ERROR: ", ""))

    if not path.is_file():
        raise HTTPException(status_code=500, detail="Download finished but the file is missing.")

    # url_for يستخدم نفس العنوان الذي اتصل به الآيفون (IP جهازك)
    video_url = str(request.url_for("get_file", name=path.name))
    return ResolveResponse(video_url=video_url, title=info.get("title") or "Video")


@app.get("/files/{name}", name="get_file")
def get_file(name: str):
    path = (DOWNLOADS / name).resolve()
    # حماية: لا نسمح بقراءة ملفات خارج مجلد downloads
    if path.parent != DOWNLOADS or not path.is_file():
        raise HTTPException(status_code=404, detail="File not found.")
    media_type = MEDIA_TYPES.get(path.suffix.lower(), "application/octet-stream")
    return FileResponse(path, media_type=media_type)
