# Proyecto final · Pronóstico de series de tiempo en producción

**Computación Avanzada — Cierre del curso**

Servicio web que pronostica el consumo eléctrico horario de un servidor: los datos se leen de **InfluxDB 2.x**, el modelo es un **SARIMA** entrenado en **Google Colab**, la API está hecha en **FastAPI** y el servicio se empaqueta en un **contenedor Docker**.

---

## Estado de la entrega

| # | Entregable | Archivo | Estado |
|---|---|---|---|
| 1 | Modelo SARIMA entrenado | `models/sarima_config.json` | ✅ |
| 2 | Notebook de entrenamiento ejecutado | `notebooks/entrenamiento_sarima_colab.ipynb` | ✅ |
| 3 | Frontend | `frontend/index.html` | ✅ |
| 4 | Contenedor | `Dockerfile`, `.dockerignore` | ✅ |
| 5 | Video de sustentación | — | 🔴 **PENDIENTE** |

---

## Video de sustentación

> 🔴 **PENDIENTE — reemplazar esta línea por el enlace antes de entregar.**
>
> Formato esperado: `https://youtu.be/XXXXXXXXXXX` (YouTube como *no listado*) o un enlace de Google Drive con permiso de lectura para el profesor. Máximo 5 minutos.
>
> **Guion sugerido:**
> 1. **Sin Docker:** `uvicorn app.main:app --host 0.0.0.0 --port 8000`, el frontend con datos reales, cambiar las horas a pronosticar y abrir `/api/salud` mostrando `"modelo_demo": false` y `"influx_configurado": true`.
> 2. **Con Docker:** `docker build -t pronostico .` y `docker run ... --env-file .env`, abrir el frontend en el otro puerto, y mostrar `docker ps` junto a `/api/salud`: el **CONTAINER ID** debe ser igual a `atendido_por` y distinto del valor de la parte sin Docker.
> 3. **Reglas:** nunca mostrar el token; terminal y navegador legibles.

---

## Serie utilizada

| Elemento | Valor |
|---|---|
| Bucket | `Consumo_elec` |
| Measurement | `Server` |
| Field | `Consumo_total` |
| Granularidad | Horaria (promedio por hora) |
| Zona horaria de los datos | UTC (la API los entrega con sufijo `Z`) |

Es el consumo eléctrico horario de un servidor. Los valores de measurement y field quedan registrados dentro del JSON exportado desde Colab, así que la API los resuelve sola sin configuración adicional.

---

## Arquitectura

```
Navegador
  frontend/index.html  (Chart.js por CDN)
        │  fetch /api/prediccion?horas=N&historia=M&confianza=0.95
        ▼
FastAPI — app/main.py
  ├── app/influx.py   → consulta Flux a InfluxDB 2.x, arma la serie horaria regular
  └── app/model.py    → reconstruye el SARIMAX y aplica los coeficientes del JSON
        │
        ├── InfluxDB Cloud  (Consumo_elec / Server / Consumo_total)
        └── models/sarima_config.json  (órdenes + parámetros + métricas)
```

El frontend lo sirve la misma API en `/`, así que **hay un solo proceso y un solo puerto**.

---

## Modelo

| Parámetro | Valor |
|---|---|
| Órdenes | `SARIMA(2,0,2)(0,1,1,24)` — estacionalidad diaria, s = 24 |
| `trend` | ninguno |
| Observaciones de entrenamiento | 720 horas |
| Rango de entrenamiento | 2026-10-12 16:00 → 2026-11-11 15:00 |
| Entrenado en | 2026-11-11 16:51 UTC (Google Colab) |
| AIC | 7596.62 |
| Versiones | statsmodels 0.15.0 · pandas 3.1.1 · numpy 2.5.4 |

### Resultados sobre las últimas 24 horas

| Modelo | MAE | RMSE | MAPE |
|---|---|---|---|
| **SARIMA(2,0,2)(0,1,1,24)** | **58.34** | **90.97** | **18.07 %** |
| Línea base ingenua (último valor) | 80.26 | 122.39 | 23.12 % |

El SARIMA reduce el error absoluto medio un **27 %** frente a la línea base ingenua.

### Por qué el modelo se exporta como JSON y no como pickle

Un pickle de `statsmodels` solo carga con **exactamente** las mismas versiones de `statsmodels`, `pandas` y `numpy` con las que fue creado, y Colab actualiza sus librerías sin avisar. Por eso se exportan únicamente las órdenes y los coeficientes estimados: la API reconstruye el `SARIMAX` con los datos recientes de InfluxDB y aplica esos parámetros con `model.filter(params)`, **sin reentrenar**. El pronóstico arranca siempre desde la última hora real disponible.

---

## API

Documentación interactiva en `/docs`.

| Método | Endpoint | Descripción |
|---|---|---|
| `GET` | `/` | Frontend |
| `GET` | `/api/prediccion?horas=&historia=&confianza=` | Pronóstico + intervalo + histórico. `horas` 1-72 (defecto 12), `historia` 0-720 (defecto 48), `confianza` en (0.5, 1) (defecto 0.95) |
| `GET` | `/api/historico?horas=` | Solo el histórico, 1-1440 horas |
| `GET` | `/api/modelo` | Órdenes, métricas y fecha de entrenamiento |
| `POST` | `/api/modelo/recargar` | Relee `models/sarima_config.json` sin reiniciar el servidor |
| `GET` | `/api/salud` | Estado del servicio y `atendido_por` |
| `GET` | `/static/<archivo>` | Archivos estáticos del frontend |

Ejemplo de respuesta de `/api/prediccion`:

```json
{
  "ultima_observacion": "2026-11-15T18:00:00Z",
  "horas_contexto_usadas": 336,
  "horas_rellenadas": 0,
  "confianza": 0.95,
  "historico": [
    {"tiempo": "2026-11-15T18:00:00Z", "valor": 241.6454}
  ],
  "prediccion": [
    {"tiempo": "2026-11-15T19:00:00Z", "prediccion": 306.4799,
     "limite_inferior": 170.6969, "limite_superior": 442.2626}
  ]
}
```

`horas_rellenadas` cuenta las horas sin dato que la API completó por interpolación o con el valor vecino: si es alto, el sensor estuvo caído y el pronóstico es menos confiable. La API entrega **UTC**; la conversión a hora de Colombia es responsabilidad del frontend.

Códigos de error: `503` si falta el modelo o la configuración de InfluxDB, `422` si se piden más de 72 horas de pronóstico, `502` si falla la consulta a InfluxDB, `404` si no hay datos en el rango. El mensaje viaja en el campo `detail`.

---

## Frontend

`frontend/index.html` es un archivo único (375 líneas) sin dependencias locales ni build. Cumple los cinco requisitos:

1. **Gráfica** con histórico (azul), pronóstico (naranja) e intervalo de confianza (banda), sobre Chart.js 4.4.7 cargado por CDN.
2. **Horas en hora de Colombia** — `toLocaleString` con `timeZone: "America/Bogota"` (UTC−5, sin horario de verano).
3. **Indicadores destacados** — cinco tarjetas: próxima hora, máximo esperado y mínimo esperado (cada uno con la hora en que ocurre), último dato real, e intervalo de confianza junto con las horas rellenadas.
4. **Controles** para elegir horas a pronosticar y horas de historia a graficar.
5. **Mensaje de error claro** — muestra el campo `detail` que devuelve la API, más un aviso cuando `horas_rellenadas > 0`.

---

## Cómo ejecutar

### Requisitos

| Componente | Versión usada | ¿Obligatorio? |
|---|---|---|
| Python | 3.12.10 | Sí, para el modo sin Docker |
| pip | 26.2.1 | Sí |
| Docker Desktop | 4.99 (engine 29.9.3, backend WSL 2) | Solo para el modo con Docker |
| Git | 2.51.0 | Recomendado |

Node.js, una base de datos local y Java **no** son necesarios.

### Credenciales

La aplicación lee cuatro variables de entorno: `INFLUX_URL`, `INFLUX_TOKEN`, `INFLUX_ORG` e `INFLUX_BUCKET`. Opcionalmente `INFLUX_MEASUREMENT` e `INFLUX_FIELD` (si no se definen, se toman del JSON del modelo).

**Las credenciales nunca van en el código ni dentro de la imagen.** En local se ponen en un archivo `.env` en la raíz (ignorado por git); en Docker se inyectan al ejecutar con `--env-file`.

`app/config.py` carga el `.env` con `load_dotenv()`, que no sobrescribe variables ya existentes en el entorno. Por eso las credenciales definidas a nivel de sistema o del contenedor tienen prioridad sobre el archivo.

### Modo 1 — Sin Docker (Windows / PowerShell)

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Abrir `http://localhost:8000`. Agregar `--reload` durante el desarrollo.

> La primera vez que se usa `--host 0.0.0.0`, Windows puede pedir permiso en el Firewall. Hay que permitir en *Redes privadas*.

### Modo 2 — Con Docker

```powershell
docker build -t pronostico .
docker run --rm -d --name pronostico -p 8001:8000 --env-file .env pronostico
docker ps --format "ID={{.ID}}  {{.Image}}  {{.Status}}  {{.Ports}}"
```

Abrir `http://localhost:8001`. Se usa el puerto **8001** en el host para poder tener el modo nativo (8000) y el contenedor (8001) corriendo a la vez y comparar los dos `atendido_por`.

Detener: `docker stop pronostico`.

### Verificación de que la imagen no lleva credenciales

```powershell
docker run --rm pronostico env | Select-String -Pattern influx   # 0 coincidencias
docker run --rm pronostico ls -a /app                             # solo app, frontend, models, requirements.txt
```

### Equivalencia de comandos en Linux / macOS / Codespaces

| Windows (PowerShell) | Linux / macOS |
|---|---|
| `.\.venv\Scripts\Activate.ps1` | `source .venv/bin/activate` |
| `python` | `python3` |
| `curl.exe` | `curl` |
| `--env-file .env` | `set -a && source .env && set +a` + `-e VAR` sin valor |
| `Start-Process http://localhost:8001` | `xdg-open http://localhost:8001` |
| `Select-String -Pattern influx` | `grep -i influx` |

En PowerShell 5.1 `curl` es un alias de `Invoke-WebRequest` y no acepta las mismas opciones, por eso se usa explícitamente `curl.exe`. En Git Bash, las rutas absolutas dentro del contenedor se convierten a rutas de Windows: hay que anteponer `MSYS_NO_PATHCONV=1`.

---

## Estructura del repositorio

```
.
├── .devcontainer/devcontainer.json   ← entorno del Codespace (Python + Docker)
├── app/
│   ├── main.py                       ← endpoints, CORS y servidor del frontend
│   ├── config.py                     ← lee las variables de entorno
│   ├── influx.py                     ← consulta Flux y arma la serie horaria
│   └── model.py                      ← carga el modelo y pronostica
├── frontend/
│   └── index.html                    ← interfaz completa (Chart.js por CDN)
├── models/
│   └── sarima_config.json            ← modelo entrenado: órdenes, parámetros, métricas
├── notebooks/
│   └── entrenamiento_sarima_colab.ipynb   ← entrenamiento ejecutado en Colab
├── scripts/
│   ├── probar_conexion.py            ← diagnóstico de la conexión a InfluxDB
│   └── crear_modelo_demo.py          ← modelo sintético para trabajar sin datos reales
├── Dockerfile                        ← imagen del servicio
├── .dockerignore                     ← excluye credenciales, notebooks y cachés
├── requirements.txt
├── .env.example
├── pruebas.http                       ← peticiones de prueba a la API
└── README.md
```

---

## Decisiones de implementación

**El `Dockerfile` copia `requirements.txt` antes que el código.** Las dependencias cambian poco y esta capa queda en caché: al reconstruir tras tocar solo el frontend, el `pip install` se salta y el build tarda segundos en vez de minutos.

**El comando de arranque usa `--host 0.0.0.0`.** Dentro de un contenedor, `127.0.0.1` solo sería visible desde el propio contenedor; `0.0.0.0` publica el servicio para que el mapeo `-p 8001:8000` lo alcance.

**El `.dockerignore` usa patrones con `**/`.** Un patrón de directorio con barra final, como `__pycache__/`, solo excluye ese nombre en la **raíz** del contexto de build. Las cachés de `app/` se filtraban a la imagen hasta prefijarlo con `**/`. Lo mismo aplica a `.venv/` y `.ipynb_checkpoints/`.

**Los `.env` no entran a la imagen.** Además de estar en `.dockerignore`, el `Dockerfile` copia carpeta por carpeta (`app/`, `frontend/`, `models/`), así que un archivo suelto en la raíz nunca se incluye. Las dos protecciones son independientes y se verifican en la sección de pruebas.

---

## Problemas encontrados durante el despliegue

**`docker build` fallaba con `lookup registry-1.docker.io: no such host`.** No era un error del `Dockerfile`: era una falla intermitente de resolución DNS dentro de la máquina virtual de Docker Desktop. El daemon descargaba imágenes sin problema, pero BuildKit no resolvía el registro. Se corrigió agregando DNS explícito en `~/.docker/daemon.json`:

```json
"dns": ["8.8.8.8", "1.1.1.1"]
```

**Solución de otros síntomas frecuentes:**

| Síntoma | Causa / solución |
|---|---|
| `Faltan variables de InfluxDB…` | Faltan en el `.env`, o en `docker run` falta `--env-file .env` |
| `(401) unauthorized` | Token mal copiado: revisar que esté completo, sin espacios |
| `InfluxDB no devolvió datos…` | Measurement o field mal escritos; usar `scripts/probar_conexion.py` |
| `No hay modelo cargado` | Falta `models/sarima_config.json`; en Docker hay que reconstruir la imagen |
| `address already in use` | Quedó un uvicorn o un contenedor vivo: `docker ps` y `docker stop pronostico` |
| La app corre en Docker pero no abre | Falta `-p`, o el arranque usa `127.0.0.1` en vez de `0.0.0.0` |
| La gráfica no se dibuja | Chart.js se carga por CDN: revisar la conexión a internet |
| Horas mostradas 5 h adelantadas | Se está mostrando el UTC sin convertir a `America/Bogota` |
| En Colab: `No module named 'influxdb_client'` | No se ejecutó la celda `!pip install` |

---

## Seguridad

- El token de InfluxDB **no está en el repositorio**: `.env` está en `.gitignore` y las credenciales nunca se escriben en el código.
- La imagen Docker **no contiene el token ni el `.env`**; se inyectan en tiempo de ejecución con `--env-file`.
- Antes de entregar, rotar el token si el archivo `.env` se compartió por cualquier medio.

---

## Apéndice · Las cinco fases del curso

| Fase | Dónde | Qué se hizo | Estado |
|---|---|---|---|
| 0 | GitHub | Se creó el repositorio, se abrió el Codespace y se cargaron las credenciales de InfluxDB como secretos | ✅ |
| 1 | Colab | Se entrenó el SARIMA y se exportó `models/sarima_config.json` | ✅ |
| 2 | Codespaces | Se diseñó el frontend a partir del esqueleto entregado | ✅ |
| 3 | Codespaces / local | Se ejecutó el servicio completo sin Docker, con datos reales | ✅ |
| 4 | Codespaces / local | Se empaquetó el servicio en un contenedor y se verificó la evidencia | ✅ |

### Detalle por fase

**Fase 0 — Repositorio y credenciales.** Se creó el repositorio a partir de la plantilla del curso y se abrió el Codespace, que instala las dependencias con el `postCreateCommand` del `.devcontainer`. Las cuatro credenciales de InfluxDB (`INFLUX_URL`, `INFLUX_TOKEN`, `INFLUX_ORG`, `INFLUX_BUCKET`) se cargaron como secretos, no en el código; el `.devcontainer` las declara y el contenedor las inyecta como variables de entorno. Se verificó la conexión con `scripts/probar_conexion.py`, que respondió `Ping: OK` y confirmó el measurement `Server` y el field `Consumo_total`.

**Fase 1 — Modelo.** El notebook recorre configuración, consulta a InfluxDB, descomposición y autocorrelación, tratamiento de atípicos, prueba de estacionariedad (ADF), búsqueda de órdenes por AIC, evaluación sobre las últimas 24 horas y exportación del JSON. Se ejecutó completo en Colab con las celdas en orden (ejecuciones 1 a 14); 13 de las 14 celdas de código conservan su salida — la restante es la celda de descarga del JSON, que no genera salida propia. En la sección 6 la verificación de consistencia reportó, como salida real, `Diferencia máxima API vs. modelo original: 0.0`.

**Fase 2 — Frontend.** Se partió de un esqueleto que solo pedía el pronóstico y lo mostraba en una tabla. Se reemplazó por una interfaz con gráfica, tarjetas de indicadores, controles y manejo de errores, cumpliendo los cinco requisitos mínimos.

**Fase 3 — Servicio sin Docker.** Se verificó con datos reales: `/api/salud` con `"modelo_cargado": true`, `"influx_configurado": true` y `"modelo_demo": false`.

**Fase 4 — Contenedor.** `docker build` sobre `python:3.12-slim`; la imagen final pesa 758 MB. La evidencia de que responde el contenedor y no el host es que el **CONTAINER ID** de `docker ps` coincide con `atendido_por` en `/api/salud`, y es distinto del valor obtenido en la Fase 3.

---

## Material de referencia

- [`pruebas.http`](pruebas.http) — peticiones de ejemplo a todos los endpoints.
- [`scripts/probar_conexion.py`](scripts/probar_conexion.py) — lista los measurements y fields del bucket y muestra las últimas horas de la serie.
- [`scripts/crear_modelo_demo.py`](scripts/crear_modelo_demo.py) — genera un modelo sintético para trabajar sin datos reales. Sobrescribe `models/sarima_config.json`, así que debe reemplazarse por el modelo real después de usarlo.
