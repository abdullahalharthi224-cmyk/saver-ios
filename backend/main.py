"""Saver backend: يحوّل رابط صفحة (مثل TikTok) إلى ملف فيديو يحمّله الآيفون.

التشغيل: SaverServer.exe، أو run.bat، أو:
    python main.py
"""
import socket
import sys
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel
from zeroconf import ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

PORT = 8000
SERVICE_TYPE = "_saver._tcp.local."  # نفس الاسم في Info.plist للتطبيق (NSBonjourServices)

# داخل ملف exe يكون __file__ في مجلد مؤقت، لذلك نستخدم مجلد الـ exe نفسه
BASE_DIR = Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).parent
# مجلد الفيديوهات المؤقتة
DOWNLOADS = (BASE_DIR / "downloads").resolve()
DOWNLOADS.mkdir(exist_ok=True)
KEEP_SECONDS = 60 * 60  # نحذف الملفات بعد ساعة

MEDIA_TYPES = {".mp4": "video/mp4", ".m4v": "video/mp4", ".mov": "video/quicktime"}



def lan_ip() -> str:
    """عنوان الجهاز في شبكة الـ Wi-Fi (لا يُرسل أي بيانات فعلياً)."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
        except OSError:
            return "127.0.0.1"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """عند التشغيل: نعلن عن الخادم في الشبكة (Bonjour) ليجده الآيفون وحده."""
    ip = lan_ip()
    url = f"http://{ip}:{PORT}"
    name = f"Saver-{socket.gethostname()}"[:40]
    info = ServiceInfo(
        SERVICE_TYPE,
        f"{name}.{SERVICE_TYPE}",
        addresses=[socket.inet_aton(ip)],
        port=PORT,
        properties={"url": url},  # التطبيق يقرأ العنوان من هنا
    )
    zeroconf = AsyncZeroconf()
    await zeroconf.async_register_service(info)
    print(f"\n  Saver server is ready: {url}\n  Keep this window open. Close it to stop.\n")
    yield
    await zeroconf.async_unregister_service(info)
    await zeroconf.async_close()


app = FastAPI(title="Saver backend", lifespan=lifespan)


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


if __name__ == "__main__":
    import uvicorn

    # 0.0.0.0 = اقبل الاتصال من أجهزة الشبكة (الآيفون)، وليس من هذا الجهاز فقط
    uvicorn.run(app, host="0.0.0.0", port=PORT)
