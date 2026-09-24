"""Genera docs/manual/Manual_Audiolibros.pdf con las capturas de docs/manual/img.

Uso: .venv\\Scripts\\python docs\\manual\\build_manual.py
"""
from pathlib import Path

from PIL import Image as PILImage
from reportlab.graphics.shapes import Drawing, Line, Polygon, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    CondPageBreak,
    Image,
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

HERE = Path(__file__).resolve().parent
IMG = HERE / "img"
OUT = HERE / "Manual_Audiolibros.pdf"
VERSION = "1.1.0"

ACCENT = colors.HexColor("#6C5CE7")
DARK = colors.HexColor("#171A21")
TEXT = colors.HexColor("#22252B")
MUTED = colors.HexColor("#6B7080")
SOFT = colors.HexColor("#F1EFFD")
WARN = colors.HexColor("#FFF6E5")
WARN_BORDER = colors.HexColor("#F0B44C")

FONTS = Path("C:/Windows/Fonts")
pdfmetrics.registerFont(TTFont("Segoe", str(FONTS / "segoeui.ttf")))
pdfmetrics.registerFont(TTFont("Segoe-Bold", str(FONTS / "segoeuib.ttf")))
pdfmetrics.registerFont(TTFont("Segoe-Italic", str(FONTS / "segoeuii.ttf")))
pdfmetrics.registerFont(TTFont("Segoe-Semi", str(FONTS / "seguisb.ttf")))
pdfmetrics.registerFont(TTFont("Mono", str(FONTS / "consola.ttf")))
pdfmetrics.registerFontFamily("Segoe", normal="Segoe", bold="Segoe-Bold", italic="Segoe-Italic")

S = {
    "body": ParagraphStyle("body", fontName="Segoe", fontSize=10.5, leading=15, textColor=TEXT, spaceAfter=6),
    "h1": ParagraphStyle("h1", keepWithNext=1, fontName="Segoe-Bold", fontSize=22, leading=28, textColor=ACCENT, spaceBefore=4, spaceAfter=10),
    "h2": ParagraphStyle("h2", keepWithNext=1, fontName="Segoe-Bold", fontSize=15, leading=20, textColor=TEXT, spaceBefore=14, spaceAfter=6),
    "h3": ParagraphStyle("h3", keepWithNext=1, fontName="Segoe-Semi", fontSize=12, leading=16, textColor=ACCENT, spaceBefore=10, spaceAfter=4),
    "caption": ParagraphStyle("caption", fontName="Segoe-Italic", fontSize=8.5, leading=11, textColor=MUTED, alignment=TA_CENTER),
    "step": ParagraphStyle("step", fontName="Segoe", fontSize=10.5, leading=15, textColor=TEXT, leftIndent=22, firstLineIndent=-22, spaceAfter=5),
    "bullet": ParagraphStyle("bullet", fontName="Segoe", fontSize=10.5, leading=15, textColor=TEXT, leftIndent=14, firstLineIndent=-10, spaceAfter=3),
    "cell": ParagraphStyle("cell", fontName="Segoe", fontSize=9.5, leading=13, textColor=TEXT),
    "cellb": ParagraphStyle("cellb", fontName="Segoe-Semi", fontSize=9.5, leading=13, textColor=TEXT),
    "callout": ParagraphStyle("callout", fontName="Segoe", fontSize=10, leading=14, textColor=TEXT),
}

CONTENT_W = A4[0] - 4 * cm


def p(text, style="body"):
    return Paragraph(text, S[style])


def code(text):
    return f'<font name="Mono" size="9.5" color="#4B3FC4">{text}</font>'


def steps(items):
    return [p(f'<font name="Segoe-Bold" color="#6C5CE7">{i}.</font>&nbsp;&nbsp;{t}', "step") for i, t in enumerate(items, 1)]


def bullets(items):
    return [p(f'<font color="#6C5CE7">•</font>&nbsp;&nbsp;{t}', "bullet") for t in items]


def callout(text, kind="tip"):
    bg, border, label = (SOFT, ACCENT, "Tip") if kind == "tip" else (WARN, WARN_BORDER, "Importante")
    t = Table([[p(f"<b>{label}:</b> {text}", "callout")]], colWidths=[CONTENT_W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("LINEBEFORE", (0, 0), (0, -1), 3, border),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    return [Spacer(1, 4), t, Spacer(1, 8)]


def _framed(path: Path, width: float, crop=None) -> Image:
    src = path
    if crop:
        im = PILImage.open(path).crop(crop)
        src = IMG / f"_crop_{path.stem}.png"
        im.save(src)
    w, h = PILImage.open(src).size
    img = Image(str(src), width=width, height=width * h / w)
    return img


def shot(name, width, caption=None, crop=None):
    img = _framed(IMG / f"{name}.png", width, crop)
    cells = [[img]]
    if caption:
        cells.append([p(caption, "caption")])
    t = Table(cells, colWidths=[width + 8])
    t.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("BOX", (0, 0), (0, 0), 0.6, colors.HexColor("#D6D8DE")),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
    ]))
    return t


def side(flowables, name, caption, width=4.2 * cm, crop=None):
    """Texto a la izquierda, captura de celular a la derecha: ahorra mucho alto de pagina."""
    img_col = width + 0.8 * cm
    t = Table([[flowables, shot(name, width, caption, crop)]], colWidths=[CONTENT_W - img_col, img_col])
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ALIGN", (1, 0), (1, 0), "CENTER"),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("RIGHTPADDING", (0, 0), (0, 0), 10),
    ]))
    return [t, Spacer(1, 8)]


def section(title):
    # Empieza pagina nueva solo si queda poco lugar (en vez de PageBreak fijo).
    return [CondPageBreak(9 * cm), p(title, "h1")]


def phones(*items, width=4.6 * cm):
    """Fila de capturas de celular: items = (nombre, leyenda[, crop])."""
    cells = [shot(i[0], width, i[1], i[2] if len(i) > 2 else None) for i in items]
    t = Table([cells], colWidths=[CONTENT_W / len(cells)] * len(cells))
    t.setStyle(TableStyle([("ALIGN", (0, 0), (-1, -1), "CENTER"), ("VALIGN", (0, 0), (-1, -1), "TOP")]))
    return [Spacer(1, 6), t, Spacer(1, 10)]


def table(rows, widths, header=True):
    data = [[p(c, "cellb" if (header and r == 0) else "cell") for c in row] for r, row in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    style = [
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DADCE3")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ]
    if header:
        style.append(("BACKGROUND", (0, 0), (-1, 0), SOFT))
    t.setStyle(TableStyle(style))
    return [t, Spacer(1, 10)]


def flow_diagram():
    w, h = CONTENT_W, 3.4 * cm
    d = Drawing(w, h)
    boxes = [
        ("Documento", "PDF · DOCX · TXT"),
        ("Generador (PC)", "voz local, sin nube"),
        ("Audiolibro", "archivo .m4b"),
        ("App Android", "escuchar y leer"),
    ]
    bw, gap = (w - 3 * 0.9 * cm) / 4, 0.9 * cm
    y, bh = 0.7 * cm, 1.9 * cm
    for i, (title, sub) in enumerate(boxes):
        x = i * (bw + gap)
        d.add(Rect(x, y, bw, bh, rx=8, ry=8, fillColor=ACCENT if i in (1, 3) else SOFT,
                   strokeColor=ACCENT, strokeWidth=1))
        fg = colors.white if i in (1, 3) else TEXT
        d.add(String(x + bw / 2, y + bh / 2 + 3, title, fontName="Segoe-Bold", fontSize=10.5,
                     fillColor=fg, textAnchor="middle"))
        d.add(String(x + bw / 2, y + bh / 2 - 11, sub, fontName="Segoe", fontSize=8,
                     fillColor=fg, textAnchor="middle"))
        if i < 3:
            ax = x + bw + 4
            d.add(Line(ax, y + bh / 2, ax + gap - 10, y + bh / 2, strokeColor=MUTED, strokeWidth=1.5))
            tip = ax + gap - 8
            d.add(Polygon([tip, y + bh / 2, tip - 6, y + bh / 2 + 4, tip - 6, y + bh / 2 - 4],
                          fillColor=MUTED, strokeColor=MUTED))
    d.add(String(w / 2, 0.1 * cm,
                 "Del documento al celular: Servidor (mismo WiFi)  o  WhatsApp / Drive / cable + Importar",
                 fontName="Segoe-Italic", fontSize=8.5, fillColor=MUTED, textAnchor="middle"))
    return d


def on_page(canvas, doc):
    if doc.page == 1:
        return
    canvas.saveState()
    canvas.setFont("Segoe", 8.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(2 * cm, 1.2 * cm, f"Audiolibros · Manual de uso · v{VERSION}")
    canvas.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"{doc.page}")
    canvas.setStrokeColor(colors.HexColor("#E3E4EA"))
    canvas.line(2 * cm, 1.55 * cm, A4[0] - 2 * cm, 1.55 * cm)
    canvas.restoreState()


def cover():
    story = [Spacer(1, 2.2 * cm)]
    story.append(Paragraph("Audiolibros", ParagraphStyle(
        "cover", fontName="Segoe-Bold", fontSize=40, leading=46, textColor=ACCENT)))
    story.append(Paragraph("Manual de uso", ParagraphStyle(
        "cover2", fontName="Segoe-Semi", fontSize=22, leading=28, textColor=TEXT, spaceAfter=10)))
    story.append(p("Convertí tus PDF, Word o TXT en audiolibros con voz natural en tu PC, "
                   "y escuchalos en el celular siguiendo el texto."))
    story.append(Spacer(1, 0.8 * cm))
    hero = Table([[shot("web_inicio", 9.6 * cm), shot("app_texto", 4.3 * cm)]],
                 colWidths=[10.4 * cm, CONTENT_W - 10.4 * cm])
    hero.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("ALIGN", (0, 0), (-1, -1), "CENTER")]))
    story.append(hero)
    story.append(Spacer(1, 1.2 * cm))
    story += table([
        ["Parte", "Qué es", "Dónde se usa"],
        ["Generador web", "Página que convierte documentos en audiolibros (.m4b) con capítulos y texto sincronizado.", "En la PC, desde el navegador"],
        ["App Audiolibros", "Reproductor con biblioteca, texto sincronizado, temporizador y segundo plano.", "En el celular Android"],
    ], [3.3 * cm, 9.2 * cm, CONTENT_W - 12.5 * cm])
    story.append(p(f'<font color="#6B7080">Versión {VERSION} · Septiembre 2026</font>'))
    story.append(PageBreak())
    return story


def contents():
    story = [p("Contenido", "h1")]
    rows = [
        ("1", "Cómo funciona"),
        ("2", "Generador web (PC): iniciar, generar, idiomas y voces"),
        ("3", "App Android: instalar, agregar libros, escuchar"),
        ("4", "Funciones de la app: texto, capítulos, temporizador, segundo plano"),
        ("5", "Problemas frecuentes"),
    ]
    for n, t in rows:
        story.append(p(f'<font name="Segoe-Bold" color="#6C5CE7">{n}</font>&nbsp;&nbsp;&nbsp;{t}', "body"))
    story += [Spacer(1, 16), p("1. Cómo funciona", "h1")]
    story.append(p("El sistema tiene dos partes que se complementan. En la <b>PC</b> corre el generador: "
                   "le das un documento y lo lee en voz alta con una voz sintética que funciona sin internet. "
                   "El resultado es un archivo <b>.m4b</b>, el formato estándar de audiolibros, que ya trae los "
                   "capítulos y el texto de cada oración adentro. En el <b>celular</b>, la app Audiolibros "
                   "reproduce ese archivo y muestra el texto a medida que avanza."))
    story.append(Spacer(1, 6))
    story.append(flow_diagram())
    story.append(Spacer(1, 10))
    story.append(p("Hay dos formas de llevar un audiolibro de la PC al celular:", "body"))
    story += bullets([
        "<b>Por el servidor</b> (celular y PC en el mismo WiFi): la app lo descarga directo del generador. "
        "También podés generar desde el celular.",
        "<b>Mandándote el archivo</b> por WhatsApp, Google Drive, OneDrive o cable, y usando <b>Importar</b> "
        "en la app. No necesita la PC encendida ni estar en la misma red.",
    ])
    story += callout("una vez que el libro está en el celular, escucharlo no necesita internet ni la PC.")
    return story


def part_web():
    story = section("2. Generador web (PC)")
    story.append(p("2.1 Qué necesitás", "h2"))
    story += bullets([
        "La PC con Windows donde está instalado el proyecto (carpeta <b>Audio Libro</b>).",
        "Un documento <b>PDF</b> (con texto seleccionable, no escaneado), <b>Word (.docx)</b> o <b>texto (.txt)</b>.",
    ])
    story.append(p("2.2 Encender el generador", "h2"))
    story += steps([
        f"En la carpeta del proyecto, hacé doble clic en {code('iniciar_web.bat')}.",
        "Se abre una ventana negra (el servidor) y el navegador en " + code("http://localhost:8000") + ".",
        "La primera vez, Windows pregunta si permitir Python en el firewall: marcá <b>Redes privadas</b> y "
        "aceptá. Esto es lo que permite que el celular se conecte.",
    ])
    story += callout("no cierres la ventana negra mientras uses el generador o la app en modo Servidor. "
                     "Cerrarla apaga el generador.", "warn")
    story.append(p("2.3 Generar un audiolibro", "h2"))
    story += steps([
        "Arrastrá el documento al recuadro punteado, o hacé clic en él para elegirlo.",
        "En <b>Idioma</b> dejá <i>Autodetectar</i> o elegí uno. Si elegís un idioma, se habilita <b>Voz</b> "
        "para elegir entre las voces disponibles (ver tabla en 2.4).",
        "Tocá <b>Generar audiolibro</b>. La barra muestra en qué etapa va: extraer texto, detectar idioma, "
        "separar capítulos, sintetizar cada capítulo y empaquetar.",
        "Al terminar aparece <b>Audiolibro listo</b> con el enlace <b>Descargar M4B</b>, y el libro se "
        "suma a la <b>Biblioteca</b> de abajo.",
    ])
    # Recortes al recuadro del formulario: la pagina completa es muy alta y deja huecos.
    story += [
        shot("web_elegido", 11 * cm, "Documento elegido, idioma Español y voz femenina de Argentina.",
             crop=(130, 160, 760, 440)),
        Spacer(1, 8),
        shot("web_progreso", 11 * cm, "Generando: la barra indica el capítulo que se está sintetizando.",
             crop=(130, 160, 760, 505)),
        Spacer(1, 8),
        shot("web_listo", 11 * cm, "Listo: enlace de descarga y el libro ya figura en la Biblioteca.",
             crop=(130, 160, 760, 570)),
    ]
    story += callout("el tiempo depende del largo del documento y de la PC. Un cuento tarda segundos; "
                     "un libro completo puede tardar bastante. Dejá la PC encendida hasta que termine.")

    story.append(p("2.4 Idiomas y voces", "h2"))
    story.append(p("Con <i>Autodetectar</i> se usa la primera voz del idioma detectado. Para elegir otra, "
                   "seleccioná el idioma a mano."))
    story += table([
        ["Idioma", "Voces disponibles"],
        ["Español", "España – Masculina · Argentina – Femenina"],
        ["English", "US – Male · US – Female"],
        ["Português (Brasil)", "Voz Faber · Voz Jeff"],
        ["Français", "Femenina · Masculina"],
        ["Italiano", "Femenina · Masculina (calidad baja)"],
        ["Deutsch", "Masculina · Femenina (calidad baja)"],
    ], [4 * cm, CONTENT_W - 4 * cm])
    story.append(p("2.5 Capítulos: cómo prepararlos", "h2"))
    story.append(p("El generador detecta un capítulo cuando encuentra un título <b>en su propia línea</b>, "
                   "con el número en cifras, romanos o palabras. Si no encuentra ninguno, divide el texto "
                   "en partes de largo parecido (<i>Parte 1, Parte 2…</i>). El texto que aparezca antes del "
                   "primer capítulo queda como <i>Inicio</i>."))
    story += table([
        ["Se detecta como capítulo", "No se detecta"],
        ["Capítulo 3 · Capítulo 3: El regreso · CAPÍTULO PRIMERO", "Una oración que empieza con “Parte de…”"],
        ["Chapter IV · Chapter Twenty-One · Parte segunda — La vuelta", "Títulos sin palabra clave (ej. solo “El regreso”)"],
        ["Chapitre 2 · Capitolo terzo · Kapitel zwei", ""],
    ], [CONTENT_W / 2, CONTENT_W / 2])
    story.append(p("2.6 Biblioteca y dirección para el celular", "h2"))
    story.append(p("La <b>Biblioteca</b> lista todos los audiolibros generados, con tamaño y cantidad de "
                   "capítulos; <b>Descargar</b> baja el archivo a la PC. Debajo del título, la página muestra "
                   "la dirección que tenés que poner en la app, por ejemplo "
                   + code("http://192.168.0.217:8000") + ". Esa dirección puede cambiar si la PC se "
                   "conecta a otra red: fijate siempre la que muestra la página."))
    return story


def part_app_basics():
    story = section("3. App Android")
    story.append(p("3.1 Instalar", "h2"))
    story += steps([
        "Descargá el instalador en el celular. Hay dos versiones:"
        "<br/>• <b>Audiolibros-1.1.0-arm64.apk</b>: para casi cualquier celular de los últimos años. Probá esta primero."
        "<br/>• <b>Audiolibros-1.1.0-armv7.apk</b>: solo si la anterior dice <i>no compatible</i> (celulares muy viejos).",
        "Abrí el archivo. Android va a pedir permiso para <b>instalar apps de origen desconocido</b>: "
        "permitilo para el navegador o el administrador de archivos que estés usando.",
        "Tocá <b>Instalar</b>. La app aparece como <b>Audiolibros</b>.",
    ])
    story.append(p("3.2 Pantalla principal", "h2"))
    story += side([
        p("La biblioteca muestra tus audiolibros, el más reciente arriba, con la cantidad de capítulos. "
          "Tocá uno para abrirlo."),
        p("Abajo a la derecha están los botones para agregar libros:"),
        *bullets([
            "<b>Servidor</b>: descargar o generar desde la PC (mismo WiFi).",
            "<b>Importar</b>: agregar un .m4b que ya tenés en el celular.",
        ]),
        p("La primera vez la biblioteca está vacía, como en la captura."),
    ], "app_vacia", "Primera vez: biblioteca vacía.")

    story.append(p("3.3 Agregar audiolibros", "h2"))
    story += side([
        p("A) Importar un archivo (sin PC, sin WiFi)", "h3"),
        p("Ideal si te mandaste el <b>.m4b</b> por WhatsApp, Drive, OneDrive, mail o cable."),
        *steps([
            "Tocá <b>Importar</b>. Se abre el selector de archivos de Android.",
            "Buscá el archivo: en <i>Descargas</i>, en la carpeta de WhatsApp, o en Drive/OneDrive "
            "(aparecen en el menú lateral si tenés esas apps instaladas).",
            "Tocá el archivo. Se copia a la biblioteca con sus capítulos y su texto.",
        ]),
    ], "app_importar", "Selector de Android (los nombres varían según el celular).")
    story.append(p("B) Descargar desde el servidor (mismo WiFi)", "h3"))
    story += steps([
        "Con el generador encendido en la PC, tocá <b>Servidor</b> y quedate en la pestaña <b>Descargar</b>.",
        "En <b>URL del servidor</b> escribí la dirección que muestra la página web (se recuerda para la próxima).",
        "Tocá <b>Buscar audiolibros en el servidor</b> y después el ícono de descarga del libro que quieras.",
    ])
    story.append(p("C) Generar desde el celular (mismo WiFi)", "h3"))
    story += steps([
        "En <b>Servidor</b>, pasá a la pestaña <b>Generar</b>.",
        "Tocá <b>Elegir PDF / DOCX / TXT</b> y seleccioná el documento del celular.",
        "Elegí <b>Idioma</b> y <b>Voz</b> (igual que en la web) y tocá <b>Generar audiolibro</b>.",
        "Podés salir de la pantalla: cuando termina, el libro se descarga solo y aparece un aviso en la biblioteca.",
    ])
    story += phones(("app_servidor_descargar", "Descargar: lista del servidor."),
                    ("app_generar_voces", "Generar: elegir la voz."),
                    ("app_generar", "Listo para generar."), width=3.9 * cm)
    story += callout("el modo Servidor solo funciona si el celular está en el <b>mismo WiFi</b> que la PC "
                     "y el generador está encendido. Con datos móviles o fuera de casa, usá Importar.", "warn")
    return story


def part_app_features():
    story = section("4. Funciones de la app")
    story.append(p("4.1 Reproductor", "h2"))
    story += side([
        *table([
            ["Control", "Qué hace"],
            ["Botón grande", "Reproducir o pausar. Si el libro terminó, pasa a “volver a empezar”."],
            ["Flechas 10 y 30", "Atrasar 10 segundos o adelantar 30."],
            ["Barra", "Arrastrala para ir a cualquier punto. Arriba se ve el capítulo actual."],
            ["1.0x", "Velocidad: de 0.75x a 2x. Se recuerda para todos los libros."],
            ["Luna", "Temporizador para dormir (ver 4.4)."],
            ["N capítulos", "Lista de capítulos (ver 4.3)."],
            ["Ícono de hoja (arriba)", "Mostrar u ocultar el texto sincronizado (ver 4.2)."],
        ], [3.2 * cm, CONTENT_W - 5 * cm - 3.2 * cm - 10]),
        p("La app recuerda dónde dejaste cada libro. Si lo terminaste, la próxima vez arranca desde el principio."),
    ], "app_reproductor", "Reproductor.")

    story.append(p("4.2 Seguir el texto mientras escuchás", "h2"))
    story += side([
        p("Tocá el <b>ícono de hoja</b> arriba a la derecha. Aparece el texto del capítulo con la oración "
          "que se está escuchando <b>resaltada en blanco</b>; la lista se mueve sola para mantenerla a la vista."),
        p("<b>Tocá cualquier oración</b> para saltar el audio a ese punto. Tocá de nuevo el ícono para "
          "volver a la vista simple."),
        p("4.3 Capítulos", "h2"),
        p("Tocá <b>N capítulos</b> (abajo a la derecha) para ver la lista con el minuto de inicio de cada "
          "uno y saltar al que quieras."),
        Spacer(1, 4),
        shot("app_capitulos", 3.4 * cm, "Lista de capítulos.", crop=(0, 1600, 1080, 2300)),
    ], "app_texto", "Texto sincronizado: la oración actual en blanco.")

    story.append(p("4.4 Temporizador para dormir", "h2"))
    story += side([
        p("Tocá la <b>luna</b> y elegí:"),
        *bullets([
            "<b>5, 15, 30, 45 o 60 minutos</b>: el tiempo solo corre mientras suena. En los últimos "
            "10 segundos baja el volumen de a poco y después pausa.",
            "<b>Al terminar este capítulo</b>: pausa justo al final del capítulo actual y queda listo "
            "para empezar el siguiente.",
            "<b>Cancelar temporizador</b>: aparece cuando hay uno activo.",
        ]),
        p("Mientras está activo, en lugar de la luna se ve la cuenta regresiva (o <i>Fin cap.</i>), "
          "y en el mini-reproductor dice cuánto falta."),
    ], "app_temporizador", "Opciones del temporizador.")

    story.append(p("4.5 Mini-reproductor y segundo plano", "h2"))
    story += side([
        p("Si volvés a la biblioteca mientras escuchás, el audio <b>sigue sonando</b> y aparece una "
          "barra abajo con el título, el progreso y el botón de pausa; tocala para volver al "
          "reproductor. El libro que suena se marca con unos auriculares."),
        p("También sigue sonando con la <b>pantalla apagada</b> o usando otra app. Los controles "
          "aparecen en la barra de notificaciones y en la pantalla de bloqueo, y funcionan los "
          "botones de auriculares y Bluetooth."),
        Spacer(1, 4),
        shot("app_notificacion", 6.5 * cm, "Controles en la barra de notificaciones.",
             crop=(0, 460, 1080, 1060)),
    ], "app_miniplayer", "Mini-reproductor (con temporizador activo).")

    story.append(p("4.6 Borrar un audiolibro", "h2"))
    story.append(p("En la biblioteca, deslizá el libro hacia la <b>izquierda</b> y confirmá. Se borra solo "
                   "del celular; en la PC sigue estando en la Biblioteca del generador."))
    return story


def part_faq():
    story = section("5. Problemas frecuentes")
    story += table([
        ["Problema", "Qué hacer"],
        ["La app no conecta al servidor",
         "Revisá: 1) celular y PC en el <b>mismo WiFi</b> (no datos móviles); 2) la ventana negra de "
         "<i>iniciar_web.bat</i> abierta; 3) la URL de la app igual a la que muestra la página web; "
         "4) Python permitido en el firewall de Windows para <i>Redes privadas</i>."],
        ["“No se pudo extraer texto del PDF”",
         "El PDF es escaneado (las páginas son imágenes). Por ahora solo funcionan PDF con texto "
         "seleccionable. Probá exportarlo desde Word o pasarlo por un programa de OCR."],
        ["“Idioma detectado no soportado”",
         "Elegí el idioma a mano en el selector. Idiomas disponibles: español, inglés, portugués, francés, "
         "italiano y alemán."],
        ["No detectó los capítulos",
         "Poné cada título en una línea sola, empezando con Capítulo/Chapter/Parte… y un número "
         "(ver 2.5). Si no, se divide en partes por largo."],
        ["Importé un libro y no tiene capítulos ni texto",
         "Los audiolibros generados con versiones anteriores a la 1.1 no traen el texto adentro del "
         "archivo. Volvé a generarlo, o descargalo con Servidor."],
        ["Android no deja instalar la app",
         "Permití <i>instalar apps de origen desconocido</i> para la app con la que abriste el archivo. "
         "Si dice “no compatible”, usá la versión armv7."],
        ["Se corta el audio con la pantalla apagada",
         "Algunas marcas (Xiaomi, Samsung, Huawei, etc.) cierran apps en segundo plano para ahorrar "
         "batería. En Ajustes → Batería, quitá la optimización para <b>Audiolibros</b>."],
        ["Una voz suena peor que las demás",
         "Italiano masculino y alemán femenino son las únicas voces disponibles para esos casos y tienen "
         "menor calidad. Probá la otra voz del idioma."],
        ["La web se comporta raro después de una actualización",
         "Cerrá la ventana negra y abrí de nuevo <i>iniciar_web.bat</i>."],
    ], [5 * cm, CONTENT_W - 5 * cm])
    story.append(p("Sobre el formato de los archivos", "h2"))
    story.append(p("Los audiolibros se guardan en formato <b>.m4b</b> estándar: además de esta app, se pueden "
                   "escuchar en otros reproductores de audiolibros o de música. En esos reproductores se "
                   "ven los capítulos, pero el texto sincronizado es una función de la app Audiolibros."))
    return story


def main():
    doc = SimpleDocTemplate(
        str(OUT), pagesize=A4,
        leftMargin=2 * cm, rightMargin=2 * cm, topMargin=1.8 * cm, bottomMargin=2 * cm,
        title="Audiolibros - Manual de uso", author="Audiolibros", subject=f"Manual v{VERSION}",
    )
    story = cover() + contents() + part_web() + part_app_basics() + part_app_features() + part_faq()
    doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
    for f in IMG.glob("_crop_*.png"):
        f.unlink()
    print(f"OK: {OUT}")


if __name__ == "__main__":
    main()
