# Proyecto final · Pronóstico de series de tiempo en producción
# Contenedor de la API FastAPI + SARIMA + InfluxDB
#
# Orden de los pasos (ver README, Fase 4):
#   1. Imagen base oficial de Python 3.12 en su versión liviana (slim).
#   2. /app como carpeta de trabajo.
#   3. Se copia SOLO requirements.txt y se instalan dependencias sin caché.
#      (Las dependencias cambian poco: este paso queda en caché de capas y
#       reconstruir tras tocar solo el código tarda segundos, no minutos.)
#   4. Se copian las carpetas que la app necesita: app/, frontend/, models/.
#      (Las credenciales se entregan con -e al ejecutar, NUNCA van en la imagen.)
#   5. Se expone el puerto 8000.
#   6. Comando de arranque: uvicorn en 0.0.0.0 — dentro del contenedor,
#      127.0.0.1 solo sería visible desde el propio contenedor; 0.0.0.0
#      publica el servicio para que -p 8000:8000 lo alcance.
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY frontend/ ./frontend/
COPY models/ ./models/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
