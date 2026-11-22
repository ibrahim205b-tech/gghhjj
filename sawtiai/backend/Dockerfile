# Sawti AI backend - CPU image (Hugging Face Spaces "Docker" SDK compatible).
# Model weights are downloaded at BUILD time from their official Hugging Face
# repos so a cold start does not re-download them. No voice data is in the image.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/opt/hf \
    SAWTI_ENGINE=silma \
    SAWTI_DATA_DIR=/tmp/sawti \
    PORT=7860

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
 && rm -rf /var/lib/apt/lists/*

# Hugging Face Spaces run containers as uid 1000.
RUN useradd -m -u 1000 user && mkdir -p /opt/hf /app && chown -R user /opt/hf /app

WORKDIR /app
COPY requirements.txt requirements-silma.txt ./
RUN pip install torch==2.8.0 torchaudio==2.8.0 torchvision==0.23.0 --index-url https://download.pytorch.org/whl/cpu \
 && pip install -r requirements.txt -r requirements-silma.txt

COPY --chown=user app ./app
USER user

# Pre-fetch weights (SILMA, Vocos vocoder, CATT diacritizer) into the image.
RUN python -c "from app.engines.silma import SilmaEngine; SilmaEngine().load(); print('weights cached')"

EXPOSE 7860
HEALTHCHECK --interval=60s --timeout=10s --start-period=300s CMD python -c "import urllib.request,os;urllib.request.urlopen('http://127.0.0.1:%s/health'%os.environ.get('PORT','7860'))"
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --workers 1 --timeout-keep-alive 30"]
