"""Собирает сценарий FigCraft для макета читалки.

Запуск из docs/mockup (Python 3, только стандартная библиотека; figcraft-cli — Windows-программа):

    python3 build_mockup.py <script.json>                 # пишет сценарий и <script>.ids.json
    figcraft-cli run <script.json> --out reader.figcraft --no-system-fonts > run.log
    python3 build_mockup.py --check <script.json> run.log # сверяет номера слоёв с выводом run
    figcraft-cli export reader.figcraft --out png --scale 2 --no-system-fonts

Слои нумеруются подряд с 2 в новом документе (страница — 1); сценарий опирается на это, чтобы ссылаться на
родителя: `parent` принимает только числовой id. Команды, которые слой не создают (`text.style`), номер не
расходуют — поэтому у Builder два метода: `_add` (создаёт слой) и `_cmd` (не создаёт). `--check` ловит
расхождение, если оно появится. `figcraft-cli run` откатывает всё при первой ошибке.

Шрифты: Roboto (интерфейс) и Merriweather (текст книги) — оба входят во встроенный набор FigCraft, поэтому
картинка одинакова на любой машине с флагом --no-system-fonts. Source Sans 3 и Source Serif 4 во встроенном
наборе отсутствуют (проверено `text.fonts` 2026-11-14).
"""
import json
import sys

W, H = 360, 800
GAP_X, GAP_Y = 80, 140
PER_ROW = 5
SANS = "Roboto"
SERIF = "Merriweather"

# ---------------------------------------------------------------- палитры
LIGHT = dict(name="Светлая", bg="#F8F4EC", surface="#FFFDF9", ink="#221D17", ink2="#675E54", line="#E3DBCE",
             accent="#A8431F", on_accent="#FFFDF9", hl="#F3DFCF", scrim="#221D17", scrim_a=0.42)
SEPIA = dict(name="Сепия", bg="#F0E4CC", surface="#F7EDDA", ink="#3A2D1F", ink2="#6B5A45", line="#DCCBAE",
             accent="#9A3D1B", on_accent="#FFF8EC", hl="#E6C9AC", scrim="#3A2D1F", scrim_a=0.42)
DARK = dict(name="Тёмная", bg="#16130F", surface="#221D18", ink="#E8E0D2", ink2="#A09584", line="#383029",
            accent="#E08A5B", on_accent="#16130F", hl="#3D2B1F", scrim="#000000", scrim_a=0.55)

# ---------------------------------------------------------------- типографика: (шрифт, начертание, кегль, интерлиньяж)
ROLES = {
    "display": (SERIF, "Bold", 26, 32),      # заголовок полки
    "title": (SANS, "Medium", 20, 26),       # заголовок экрана, листа, диалога
    "title_s": (SANS, "Medium", 16, 22),     # заголовок в шапке чтения, пункт списка
    "body": (SANS, "Regular", 16, 22),
    "label": (SANS, "Medium", 15, 20),       # кнопки
    "small": (SANS, "Regular", 14, 20),
    "small_m": (SANS, "Medium", 14, 20),
    "caption": (SANS, "Regular", 13, 18),
    "over": (SANS, "Medium", 12, 16),        # надписи разделов
    "book": (SERIF, "Regular", 16, 27),      # текст книги
    "book_i": (SERIF, "Italic", 14, 22),     # эпиграф, стихи
    "book_cap": (SERIF, "Italic", 13, 20),   # подпись к картинке
    "book_h": (SERIF, "Bold", 22, 32),       # заголовок главы
    "book_title": (SERIF, "Bold", 16, 22),   # название книги в списке
    "book_title_l": (SERIF, "Bold", 18, 24), # название книги в карточке «Продолжить»
}
LINE = 27  # шаг строки текста книги: высота страницы кратна ему, поэтому страница режется по границе строки

# ---------------------------------------------------------------- иконки: Material Icons (filled), клетка 24×24
ICONS = {
    "back": "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z",
    "close": "M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z",
    "play": "M8 5v14l11-7z",
    "pause": "M6 19h4V5H6v14zm8-14v14h4V5h-4z",
    "prev": "M6 6h2v12H6zm3.5 6l8.5 6V6z",
    "next": "M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z",
    "add": "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z",
    "toc": "M3 13h2v-2H3v2zm0 4h2v-2H3v2zm0-8h2V7H3v2zm4 4h14v-2H7v2zm0 4h14v-2H7v2zM7 7v2h14V7H7z",
    "phones": "M12 1c-4.97 0-9 4.03-9 9v7c0 1.66 1.34 3 3 3h3v-8H5v-2c0-3.87 3.13-7 7-7s7 3.13 7 7v2h-4v8h3c1.66 0 "
              "3-1.34 3-3v-7c0-4.97-4.03-9-9-9z",
    "check": "M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z",
    "chevron": "M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z",
    "expand": "M16.59 8.59L12 13.17 7.41 8.59 6 10l6 6 6-6z",
    "download": "M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z",
    "settings": "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12"
                "-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 "
                "0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08"
                ".47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22"
                ".37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54"
                "c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 "
                "15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z",
    "bedtime": "M12.34 2.02C6.59 1.82 2 6.42 2 12c0 5.52 4.48 10 10 10 3.71 0 6.93-2.02 8.66-5.02-7.51-.25-12.09-8.43"
               "-8.32-14.96z",
    "open": "M19 19H5V5h7V3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2v-7h-2v7zM14 3v2h3.59l-9.83 9.83 "
            "1.41 1.41L19 6.41V10h2V3h-7z",
    "locate": "M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3A8.994 8.994 0 0 0 13 3.06V1h-2v2.06A"
              "8.994 8.994 0 0 0 3.06 11H1v2h2.06A8.994 8.994 0 0 0 11 20.94V23h2v-2.06A8.994 8.994 0 0 0 20.94 13H23v"
              "-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z",
    "stop": "M6 6h12v12H6z",
}
# рамка рисунка внутри клетки 24×24: (x, y, ширина, высота) — снято node.get с несмасштабированных векторов
ICON_BOX = {
    "back": (4, 4, 16, 16), "close": (5, 5, 14, 14), "play": (8, 5, 11, 14), "pause": (6, 5, 12, 14),
    "prev": (6, 6, 12, 12), "next": (6, 6, 12, 12), "add": (5, 5, 14, 14), "toc": (3, 7, 18, 10),
    "phones": (3, 1, 18, 19), "check": (3.41, 5.59, 17.59, 13.41), "chevron": (8.59, 6, 7.41, 12),
    "expand": (6, 8.59, 12, 7.41), "download": (5, 3, 14, 17), "settings": (2.66, 2.4, 18.68, 19.2),
    "bedtime": (2, 2.01, 18.66, 19.99), "open": (3, 3, 18, 18), "locate": (1, 1, 22, 22), "stop": (6, 6, 12, 12),
}

# ---------------------------------------------------------------- тексты (общественное достояние)
CH1 = [
    "Говорили, что на набережной появилось новое лицо: дама с собачкой. Дмитрий Дмитрич Гуров, проживший в Ялте "
    "уже две недели и привыкший тут, тоже стал интересоваться новыми лицами. Сидя в павильоне у Верне¹, он видел, "
    "как по набережной прошла молодая дама, невысокого роста блондинка, в берете; за нею бежал белый шпиц.",
    "И потом он встречал её в городском саду и на сквере, по нескольку раз в день. Она гуляла одна, всё в том же "
    "берете, с белым шпицем; никто не знал, кто она, и называли её просто так: дама с собачкой.",
    "«Если она здесь без мужа и без знакомых, — соображал Гуров, — то было бы не лишнее познакомиться с ней».",
    "Ему не было ещё сорока, но у него была уже дочь двенадцати лет и два сына гимназиста. Его женили рано, когда "
    "он был ещё студентом второго курса, и теперь жена казалась в полтора раза старше его.",
    "Это была женщина высокая, с тёмными бровями, прямая, важная, солидная и, как она сама себя называла, "
    "мыслящая. Она много читала, не писала в письмах ъ, называла мужа не Дмитрием, а Димитрием, а он втайне "
    "считал её недалёкой, узкой, неизящной, боялся её и не любил бывать дома.",
]
LATER = [
    "Изменять ей он начал уже давно, изменял часто и, вероятно, поэтому о женщинах отзывался почти всегда дурно, "
    "и когда в его присутствии говорили о них, то он называл их так: — Низшая раса!",
    "Ему казалось, что он достаточно научен горьким опытом, чтобы называть их как угодно, но всё же без «низшей "
    "расы» он не мог бы прожить и двух дней. В обществе мужчин ему было скучно, не по себе, с ними он был "
    "неразговорчив, холоден, но когда находился среди женщин, то чувствовал себя свободно и знал, о чём говорить "
    "с ними и как держать себя; и даже молчать с ними ему было легко.",
    "В его наружности, в характере, во всей его натуре было что-то привлекательное, неуловимое, что располагало к "
    "нему женщин, манило их; он знал об этом, и самого его тоже какая-то сила влекла к ним.",
]
NOTE = "Павильон Верне — кафе-кондитерская на ялтинской набережной."

BOOK = "Дама с собачкой. Рассказы"
COVERS = {"Дама с собачкой. Рассказы": "#7A3B2E", "Мастер и Маргарита": "#3D5A4C", "Война и мир": "#40506B",
          "Капитанская дочка": "#6B5A3A", "Степь": "#5B3F5E"}


class Builder:
    def __init__(self):
        self.steps = []
        self.ids = []          # ожидаемый id для каждого шага (None — шаг слоя не создаёт)
        self.next_id = 2
        self.n_screens = 0

    # -- низкий уровень
    def _add(self, command, params):
        params.setdefault("select", False)
        self.steps.append({"command": command, "params": params})
        node_id = self.next_id
        self.ids.append(node_id)
        self.next_id += 1
        return node_id

    def _cmd(self, command, params):
        self.steps.append({"command": command, "params": params})
        self.ids.append(None)

    # -- примитивы
    def screen(self, name, t):
        i = self.n_screens
        self.n_screens += 1
        x, y = (i % PER_ROW) * (W + GAP_X), (i // PER_ROW) * (H + GAP_Y)
        return self._add("frame.create", {"x": x, "y": y, "width": W, "height": H, "name": name,
                                          "props": {"fill": t["bg"], "clip": True}})

    def frame(self, parent, x, y, w, h, name="Фрейм", **props):
        props.setdefault("fill", "none")
        return self._add("frame.create", {"x": x, "y": y, "width": w, "height": h, "parent": parent, "name": name,
                                          "props": props})

    def rect(self, parent, x, y, w, h, fill, radius=0, name="Прямоугольник", **props):
        props.update(fill=fill, cornerRadius=radius)
        return self._add("shape.rectangle", {"x": x, "y": y, "width": w, "height": h, "parent": parent,
                                             "name": name, "props": props})

    def ellipse(self, parent, x, y, d, fill, name="Круг", **props):
        props.update(fill=fill)
        return self._add("shape.ellipse", {"x": x, "y": y, "width": d, "height": d, "parent": parent,
                                           "name": name, "props": props})

    def text(self, parent, x, y, s, role, color, width=None, name=None, **props):
        font, style, size, lh = ROLES[role]
        for unit in (" МБ", " $", " %"):  # число не отрывается от единицы
            s = s.replace(unit, " " + unit[1:])
        props = {"fontFamily": font, "fontStyle": style, "fontSize": size, "lineHeight": lh, "fill": color,
                 **props}
        params = {"text": s, "x": x, "y": y, "parent": parent, "props": props}
        if width is not None:
            params["width"] = width
        if name:
            params["name"] = name
        return self._add("text.create", params)

    def style(self, node_id, start, end, **props):
        self._cmd("text.style", {"id": node_id, "start": start, "end": end, **props})

    def icon(self, parent, x, y, name, color, size=24):
        """Иконка в клетке size×size с левым верхним углом (x, y): фрейм-клетка и вектор в нём."""
        cell = self.frame(parent, x, y, size, size, "icon/" + name)
        k = size / 24
        ox, oy, bw, bh = ICON_BOX[name]
        # vector.create кладёт левый край рисунка в x + несмасштабированное смещение рамки
        self._add("vector.create", {"path": ICONS[name], "closed": True, "x": ox * k - ox, "y": oy * k - oy,
                                    "width": bw * k, "height": bh * k, "parent": cell, "name": name,
                                    "props": {"fill": color, "stroke": "none"}})
        return cell


b = Builder()


# ================================================================ компоненты
def status_bar(s, t, fill=None):
    """Строка состояния Android, 28 dp. На экране чтения без панелей её нет (полноэкранный режим)."""
    if fill:
        b.rect(s, 0, 0, W, 28, fill, name="Строка состояния")
    b.text(s, 16, 6, "12:30", "small_m", t["ink"], name="Время")
    b.rect(s, W - 16 - 20, 10, 20, 10, "none", radius=2.5, name="Батарея", stroke=t["ink"], strokeWeight=1.2)
    b.rect(s, W - 16 - 20 + 2, 12, 12, 6, t["ink"], radius=1)
    b.rect(s, W - 16 + 1, 13, 2, 4, t["ink"], radius=1)


def app_bar(s, t, title, sub=None, left="back", right=()):
    """Шапка 28 + 56 dp: значок слева, заголовок, значки справа. Клетки касания 48 dp."""
    b.rect(s, 0, 0, W, 84, t["surface"], name="Шапка")
    b.rect(s, 0, 84, W, 1, t["line"], name="Линия")
    status_bar(s, t)
    b.icon(s, 16, 44, left, t["ink"])
    tw = W - 64 - 16 - 48 * len(right)
    if sub:
        b.text(s, 64, 36, title, "title_s", t["ink"], width=tw, maxLines=1)
        b.text(s, 64, 58, sub, "caption", t["ink2"], width=tw, maxLines=1)
    else:
        b.text(s, 64, 43, title, "title", t["ink"], width=tw, maxLines=1)
    x = W - 4 - 48
    for item in reversed(right):
        if item == "Аа":
            b.text(s, x, 42, "Аа", "book_h", t["ink"], width=48, textAlign="center", fontSize=20, lineHeight=28,
                   name="Вид текста")
        else:
            b.icon(s, x + 12, 44, item, t["ink"])
        x -= 48


def button(parent, x, y, w, label, t, icon=None, kind="filled", h=48, name="Кнопка", align="center"):
    """Кнопка-пилюля на автораскладке. w=None — по содержимому. kind: filled | outlined | text.

    align="max" — текстовая кнопка у правого края: подпись прижата к правому полю, клетка касания w×h."""
    fg = t["on_accent"] if kind == "filled" else t["accent"]
    props = dict(cornerRadius=h / 2, layout="horizontal", mainAlign=align, crossAlign="center", gap=8,
                 fill=t["accent"] if kind == "filled" else "none")
    if kind == "outlined":
        props.update(stroke=t["accent"], strokeWeight=1.5, strokeAlign="inside")
    if w is None:
        props.update(sizingH="hug", padding=[0, 20 if kind != "text" else 12, 0, 20 if kind != "text" else 12])
        w = 100
    f = b.frame(parent, x, y, w, h, name, **props)
    if icon:
        b.icon(f, 0, 0, icon, fg, size=20)
    b.text(f, 0, 0, label, "label", fg)
    return f


def centered_row(parent, y, h, name="Ряд"):
    """Полоса во всю ширину, центрирующая содержимое по горизонтали."""
    return b.frame(parent, 0, y, W, h, name, layout="horizontal", mainAlign="center", crossAlign="center")


def spinner(parent, x, y, d, color):
    b.ellipse(parent, x, y, d, color, name="Индикатор ожидания", arcStart=-90, arcSweep=270, arcInner=0.78)


def radio(parent, x, y, on, t):
    b.ellipse(parent, x, y, 20, "none", name="Переключатель", stroke=t["accent"] if on else t["ink2"],
              strokeWeight=2, strokeAlign="inside")
    if on:
        b.ellipse(parent, x + 5, y + 5, 10, t["accent"])


def scrim(s, t):
    b.rect(s, 0, 0, W, H, t["scrim"], name="Затемнение", opacity=t["scrim_a"])


def sheet(s, t, h, title=None):
    """Нижний лист: скругление 24 сверху, ручка, заголовок. Возвращает y верха листа."""
    scrim(s, t)
    y = H - h
    b.rect(s, 0, y, W, h, t["surface"], radius=[24, 24, 0, 0], name="Лист")
    b.rect(s, W / 2 - 16, y + 10, 32, 4, t["line"], radius=2, name="Ручка")
    if title:
        b.text(s, 24, y + 30, title, "title", t["ink"])
    return y


def dialog(s, t, h, title, body, confirm, cancel="Отмена"):
    """Диалог подтверждения по центру экрана. h подобрана под две строки заголовка/текста."""
    scrim(s, t)
    y = (H - h) // 2
    b.rect(s, 24, y, W - 48, h, t["surface"], radius=24, name="Диалог")
    b.text(s, 48, y + 24, title, "title", t["ink"], width=W - 96)
    b.text(s, 48, y + 64, body, "body", t["ink2"], width=W - 96)
    button(s, W - 48 - 112, y + h - 72, 112, confirm, t)
    button(s, W - 48 - 112 - 8 - 96, y + h - 72, 96, cancel, t, kind="text")


def cover(parent, x, y, w, h, title, t):
    """Обложка-заглушка: цветной прямоугольник с названием. Книга без обложки — первая буква названия."""
    color = COVERS.get(title)
    if color is None:
        b.rect(parent, x, y, w, h, t["line"], radius=3, name="Заглушка обложки")
        b.text(parent, x, y + h / 2 - 16, title[0], "book_h", t["ink2"], width=w, textAlign="center")
        return
    b.rect(parent, x, y, w, h, color, radius=3, name="Обложка")
    b.rect(parent, x + 3, y, 1.5, h, "#FFFFFF", opacity=0.18, name="Корешок")
    big = w >= 80
    size = 13 if big else 6.5
    b.text(parent, x + (8 if big else 5), y + (8 if big else 6), title, "book_title", "#FFF8EC",
           width=w - (14 if big else 6), fontSize=size, lineHeight=round(size * 1.3))


def page(parent, t, y, avail, paras=CH1, heading=None, highlight=None, footnote_mark=None):
    """Страница книги: колонка 312 dp (поля 24), автораскладка считает высоты абзацев.

    Высота страницы кратна LINE, поэтому нижняя строка не режется пополам — абзац продолжается на следующей
    странице, как в настоящей разбивке."""
    head_h = 4 * LINE if heading else 0
    h = head_h + (avail - head_h) // LINE * LINE
    col = b.frame(parent, 16, y, W - 32, h, "Страница", layout="vertical", gap=0, clip=True)
    if heading:
        # заголовок прижат к низу своего блока: шапка с панелями (до y=84) его не перекрывает
        hw = b.frame(col, 0, 0, W - 32, head_h, "Заголовок главы", layout="vertical", mainAlign="max",
                     crossAlign="center", sizingH="fill", padding=[0, 0, 14, 0])
        b.text(hw, 0, 0, heading, "book_h", t["ink"], textAlign="center")
    for i, p in enumerate(paras):
        wrap = b.frame(col, 0, 0, W - 32, LINE, "Абзац", layout="vertical", padding=[0, 8, 0, 8], cornerRadius=6,
                       sizingH="fill", sizingV="hug", fill=t["hl"] if i == highlight else "none")
        tid = b.text(wrap, 0, 0, p, "book", t["ink"], paragraphIndent=24, sizingH="fill",
                     textAutoResize="height")
        mark = p.find("¹")
        if mark >= 0:
            b.style(tid, mark, mark + 1, textFills=[t["accent"]], fontStyle="Bold")
    return col, h


def footer(s, t, text="34 %"):
    b.text(s, 0, H - 38, text, "caption", t["ink2"], width=W, textAlign="center", name="Доля книги")


# ---------------------------------------------------------------- плеер
PLAYER_H = 152
END_H = 80


def player(s, t, state="playing", y0=H - PLAYER_H, timer=None, card=False):
    """Панель прослушивания, 152 dp.

    Ряд A (48): голос — или словами состояние, когда звука нет; справа «закрыть» (остановить прослушивание).
    Ряд B (64): скорость · назад · играть/пауза · вперёд · таймер сна."""
    p = b.frame(s, 0, y0, W, PLAYER_H, "Плеер — " + state, fill=t["surface"], clip=True,
                cornerRadius=16 if card else 0)
    if not card:
        b.rect(p, 0, 0, W, 1, t["line"], name="Линия")
    if state in ("preparing", "waiting"):
        spinner(p, 20, 20, 16, t["accent"])
        b.text(p, 46, 18, "Готовлю голос…" if state == "preparing" else "Жду связь…", "small_m", t["ink2"])
    else:
        chip = b.frame(p, 4, 4, 160, 48, "Голос", layout="horizontal", crossAlign="center", gap=4,
                       sizingH="hug", padding=[0, 8, 0, 12])
        b.text(chip, 0, 0, "Голос:", "small", t["ink2"])
        b.text(chip, 0, 0, "Aoede", "small_m", t["ink"])
        b.icon(chip, 0, 0, "expand", t["ink2"], size=20)
    b.icon(p, W - 16 - 24, 16, "close", t["ink2"])
    # ряд B
    b.text(p, 12, 82, "1,25×", "small_m", t["ink"], width=56, textAlign="center", name="Скорость")
    b.icon(p, 84 + 8, 76, "prev", t["ink"], size=32)
    b.ellipse(p, W / 2 - 32, 60, 64, t["accent"], name="Играть/пауза")
    b.icon(p, W / 2 - 16, 76, "play" if state == "paused" else "pause", t["on_accent"], size=32)
    b.icon(p, W - 84 - 48 + 8, 76, "next", t["ink"], size=32)
    if timer:
        b.icon(p, W - 12 - 56 + 18, 72, "bedtime", t["accent"], size=20)
        b.text(p, W - 12 - 56, 94, timer, "over", t["accent"], width=56, textAlign="center")
    else:
        b.icon(p, W - 12 - 56 + 16, 80, "bedtime", t["ink"])
    return p


def player_stopped(parent, t, title, detail, action=None):
    """Остановка с ошибкой (`stopped`): своими словами что случилось, ответ Google, действие и «Слушать».

    Высота по содержимому (автораскладка): текст сверху, кнопки сразу под ним, крестик — в строке заголовка."""
    p = b.frame(parent, 0, 0, W, 100, "Плеер — stopped", fill=t["surface"], cornerRadius=16, layout="vertical",
                padding=[16, 16, 20, 16], gap=16, sizingV="hug")
    top = b.frame(p, 0, 0, W - 32, 40, "Сообщение", layout="horizontal", gap=16, sizingH="fill", sizingV="hug")
    msg = b.frame(top, 0, 0, W - 72, 40, "Текст", layout="vertical", gap=6, sizingH="fill", sizingV="hug")
    b.text(msg, 0, 0, title, "title_s", t["ink"], sizingH="fill", textAutoResize="height")
    b.text(msg, 0, 0, detail, "caption", t["ink2"], sizingH="fill", textAutoResize="height")
    b.icon(top, 0, 0, "close", t["ink2"])
    row = b.frame(p, 0, 0, W - 32, 48, "Действия", layout="horizontal", gap=8, sizingH="fill")
    if action:
        button(row, 0, 0, 160, action[0], t, icon=action[1])
        button(row, 0, 0, 160, "Слушать", t, icon="play", kind="outlined")
    else:
        button(row, 0, 0, W - 32, "Слушать", t, icon="play")
    return p


def listening(s, t, highlight=1):
    page(s, t, 40, H - PLAYER_H - 8 - 40, highlight=highlight, heading="I")
    player(s, t, "playing")


# ================================================================ экраны
t = LIGHT
SHELF = [("Мастер и Маргарита", "Михаил Булгаков", "12 %"), ("Война и мир", "Лев Толстой", "новая"),
         ("Записки охотника", "Иван Тургенев", "58 %"), ("Капитанская дочка", "Александр Пушкин", "3 %"),
         ("Степь", "Антон Чехов", "прочитана")]


def shelf_header(s, t):
    status_bar(s, t)
    b.text(s, 16, 44, "Книги", "display", t["ink"])
    b.icon(s, W - 16 - 24, 48, "settings", t["ink"])


def continue_card(s, t, y):
    b.rect(s, 16, y, W - 32, 172, t["surface"], radius=16, name="Карточка «Продолжить»", stroke=t["line"],
           strokeWeight=1, strokeAlign="inside")
    cover(s, 32, y + 16, 96, 140, BOOK, t)
    x = 144
    b.text(s, x, y + 18, "ПРОДОЛЖИТЬ", "over", t["accent"], letterSpacing="6%")
    b.text(s, x, y + 38, BOOK, "book_title_l", t["ink"], width=W - 32 - x, maxLines=2)
    b.text(s, x, y + 90, "Антон Чехов", "small", t["ink2"])
    b.text(s, x, y + 122, "Дама с собачкой · I · 34 %", "caption", t["ink2"], width=W - 32 - x, maxLines=1)
    b.rect(s, x, y + 146, W - 32 - x - 16, 4, t["line"], radius=2, name="Прогресс")
    b.rect(s, x, y + 146, round((W - 32 - x - 16) * 0.34), 4, t["accent"], radius=2)


def shelf_row(s, t, y, title, author, mark, last=False):
    cover(s, 16, y + 10, 52, 72, title, t)
    b.text(s, 84, y + 22, title, "book_title", t["ink"], width=W - 84 - 16 - 80, maxLines=1)
    b.text(s, 84, y + 48, author, "small", t["ink2"], width=W - 84 - 16 - 80, maxLines=1)
    b.text(s, W - 16 - 76, y + 36, mark, "caption", t["ink2"], width=76, textAlign="right")
    if not last:
        b.rect(s, 84, y + 91, W - 84 - 16, 1, t["line"], name="Разделитель")


def fab(s, t):
    b.rect(s, W - 16 - 56, H - 24 - 56, 56, 56, t["accent"], radius=16, name="Добавить книгу",
           effects=[{"type": "dropShadow", "color": "#00000033", "offset": [0, 2], "radius": 6}])
    b.icon(s, W - 16 - 56 + 16, H - 24 - 56 + 16, "add", t["on_accent"])


# ---- 01 Полка
def shelf(s, t):
    shelf_header(s, t)
    continue_card(s, t, 100)
    for i, row in enumerate(SHELF):
        shelf_row(s, t, 284 + i * 92, *row, last=i == len(SHELF) - 1)
    fab(s, t)


s = b.screen("01 Полка", t)
shelf(s, t)

# ---- 02 Полка — пустая
s = b.screen("02 Полка — пустая", t)
shelf_header(s, t)
for dx, dy, c in ((-46, 14, t["line"]), (0, 0, t["hl"]), (46, 14, t["line"])):
    b.rect(s, W / 2 - 22 + dx, 236 + dy, 44, 64, c, radius=4, name="Книжка")
b.text(s, 32, 336, "Здесь будут ваши книги", "title", t["ink"], width=W - 64, textAlign="center",
       fontFamily=SERIF, fontStyle="Bold")
b.text(s, 40, 376, "Добавьте файл FB2, EPUB или TXT кнопкой ниже — или откройте его из другого приложения "
       "через «Открыть с помощью».", "body", t["ink2"], width=W - 80, textAlign="center")
r = centered_row(s, 476, 48)
button(r, 0, 0, None, "Добавить книгу", t, icon="add")

# ---- 03 Полка — добавление
s = b.screen("03 Полка — добавление", t)
shelf_header(s, t)
y = 100
b.rect(s, 16, y + 10, 52, 72, t["hl"], radius=3, name="Обложка — добавляется")
spinner(s, 16 + 14, y + 10 + 24, 24, t["accent"])
b.text(s, 84, y + 22, "tolstoy_voyna_i_mir.fb2.zip", "title_s", t["ink"], width=W - 84 - 16, maxLines=1)
b.text(s, 84, y + 48, "Добавляется…", "small", t["ink2"])
b.rect(s, 84, y + 91, W - 100, 1, t["line"])
y += 92
b.rect(s, 16, y + 10, 52, 72, "none", radius=3, name="Обложка — ошибка", stroke=t["line"], strokeWeight=1.5,
       dashes=[4, 3])
b.text(s, 84, y + 14, "scan_2019.pdf", "title_s", t["ink"], width=W - 84 - 64, maxLines=1)
b.text(s, 84, y + 38, "Этот формат не поддерживается", "small", t["ink"], width=W - 84 - 64)
b.icon(s, W - 16 - 24, y + 34, "close", t["ink2"])
b.rect(s, 84, y + 91, W - 100, 1, t["line"])
y += 92
b.rect(s, 16, y + 10, 52, 72, "none", radius=3, name="Обложка — ошибка", stroke=t["line"], strokeWeight=1.5,
       dashes=[4, 3])
b.text(s, 84, y + 14, "rasskazy.fb2", "title_s", t["ink"], width=W - 84 - 64, maxLines=1)
b.text(s, 84, y + 38, "Не удалось прочитать книгу", "small", t["ink"], width=W - 84 - 64)
b.text(s, 84, y + 60, "XML: unexpected EOF, line 1204", "caption", t["ink2"], width=W - 84 - 64,
       maxLines=1)
b.icon(s, W - 16 - 24, y + 34, "close", t["ink2"])
continue_card(s, t, y + 104)
shelf_row(s, t, y + 104 + 184, *SHELF[0])
shelf_row(s, t, y + 104 + 184 + 92, *SHELF[1])
fab(s, t)

# ---- 04 Полка — меню книги
s = b.screen("04 Полка — меню книги", t)
shelf(s, t)
y = sheet(s, t, 264)
cover(s, 24, y + 32, 44, 62, "Война и мир", t)
b.text(s, 84, y + 38, "Война и мир", "book_title", t["ink"], width=W - 84 - 24)
b.text(s, 84, y + 62, "Лев Толстой · 96 МБ", "small", t["ink2"])
b.rect(s, 0, y + 112, W, 1, t["line"])
b.text(s, 24, y + 130, "Удалить озвучку", "body", t["ink"])
b.text(s, W - 24 - 100, y + 130, "38 МБ", "body", t["ink2"], width=100, textAlign="right")
b.text(s, 24, y + 186, "Удалить книгу", "body", t["ink"])

# ---- 05 Полка — удаление
s = b.screen("05 Полка — удаление", t)
shelf(s, t)
dialog(s, t, 204, "Удалить «Война и мир»?",
       "Книга и её озвучка будут удалены с телефона. Освободится 96 МБ.", "Удалить")

# ---- 06 Чтение
s = b.screen("06 Чтение", t)
page(s, t, 40, H - 44 - 40, heading="I")
footer(s, t)

# ---- 07 Чтение — панели
s = b.screen("07 Чтение — панели", t)
page(s, t, 40, H - 44 - 40, heading="I")
footer(s, t)
app_bar(s, t, BOOK, "Дама с собачкой · I", right=("toc", "Аа"))
y = H - 168
b.rect(s, 0, y, W, 168, t["surface"], name="Нижняя панель")
b.rect(s, 0, y, W, 1, t["line"])
track = W - 48
b.rect(s, 24, y + 30, track, 4, t["line"], radius=2, name="Ползунок по книге")
b.rect(s, 24, y + 30, round(track * 0.34), 4, t["accent"], radius=2)
b.ellipse(s, 24 + round(track * 0.34) - 10, y + 22, 20, t["accent"], name="Бегунок")
b.text(s, 24, y + 52, "34 % книги", "caption", t["ink2"])
button(s, 16, y + 88, W - 32, "Слушать", t, icon="phones", h=52)

# ---- 08 Чтение — стихи и картинка
s = b.screen("08 Чтение — стихи и картинка", t)
col = b.frame(s, 16, 40, W - 32, H - 84, "Страница", layout="vertical", gap=0, clip=True)
hw = b.frame(col, 0, 0, W - 32, 4 * LINE, "Заголовок главы", layout="vertical", mainAlign="center",
             crossAlign="center", sizingH="fill", gap=4)
b.text(hw, 0, 0, "Глава I", "book_h", t["ink"], textAlign="center")
b.text(hw, 0, 0, "Сержант гвардии", "book_i", t["ink"], textAlign="center", fontSize=16, lineHeight=24)
ep = b.frame(col, 0, 0, W - 32, 100, "Эпиграф — стихи", layout="vertical", padding=[4, 8, 16, 24], gap=4,
             sizingH="fill", sizingV="hug")
b.text(ep, 0, 0, "— Был бы гвардии он завтра ж капитан.\n— Того не надобно; пусть в армии послужит.\n"
       "— Изрядно сказано! пускай его потужит…\n. . . . . . . . . . . . . . .\nДа кто его отец?",
       "book_i", t["ink"], sizingH="fill", textAutoResize="height", fontSize=13, lineHeight=21)
b.text(ep, 0, 0, "Княжнин", "book_i", t["ink2"], sizingH="fill", textAutoResize="height", textAlign="right",
       fontSize=13, lineHeight=21)
wrap = b.frame(col, 0, 0, W - 32, LINE, "Абзац", layout="vertical", padding=[0, 8, 0, 8], sizingH="fill",
               sizingV="hug")
b.text(wrap, 0, 0, "Отец мой Андрей Петрович Гринёв в молодости своей служил при графе Минихе и вышел в "
       "отставку премьер-майором в 17.. году. С тех пор жил он в своей Симбирской деревне, где и женился на "
       "девице Авдотье Васильевне Ю., дочери бедного тамошнего дворянина.", "book", t["ink"], paragraphIndent=24,
       sizingH="fill", textAutoResize="height")
pic = b.frame(col, 0, 0, W - 32, 100, "Картинка", layout="vertical", padding=[20, 8, 0, 8], gap=8,
              sizingH="fill", sizingV="hug", crossAlign="center")
img = b.frame(pic, 0, 0, W - 48, 160, "Изображение", fill="#D8CBB4", cornerRadius=2, clip=True)
b.ellipse(img, 214, 24, 34, "#EFE4D0", name="Солнце")
b._add("vector.create", {"path": "M0 160 L84 76 L134 120 L204 52 L312 160 Z", "closed": True, "x": 0, "y": 0,
                         "parent": img, "name": "Горы", "props": {"fill": "#B9A587", "stroke": "none"}})
b.text(pic, 0, 0, "Иллюстрация к первой главе", "book_cap", t["ink2"], width=W - 80, textAlign="center")
footer(s, t, "2 %")

# ---- 09 Вид текста (сепия выбрана — страница за листом уже в сепии)
ts = SEPIA
s = b.screen("09 Вид текста", ts)
page(s, ts, 40, H - 44 - 40, heading="I")
y = sheet(s, ts, 300, "Вид текста")
b.text(s, 24, y + 76, "Размер", "over", ts["ink2"])
b.text(s, 16, y + 98, "А", "book", ts["ink"], width=48, textAlign="center", fontSize=15, lineHeight=48)
b.text(s, W - 16 - 48, y + 98, "А", "book", ts["ink"], width=48, textAlign="center", fontSize=26, lineHeight=48)
steps_x0, steps_w = 72, W - 72 * 2
for i in range(6):
    cx = steps_x0 + steps_w * i / 5
    on = i == 2
    d = 16 if on else 8
    b.ellipse(s, cx - d / 2, y + 122 - d / 2, d, ts["accent"] if i <= 2 else ts["line"], name="Ступень размера")
b.rect(s, steps_x0, y + 121, steps_w * 2 / 5, 2, ts["accent"], name="Шкала")
b.rect(s, steps_x0 + steps_w * 2 / 5, y + 121, steps_w * 3 / 5, 2, ts["line"])
b.text(s, 24, y + 162, "Тема", "over", ts["ink2"])
themes = [("Как в системе", LIGHT["bg"], DARK["bg"]), ("Светлая", LIGHT["bg"], None),
          ("Сепия", SEPIA["bg"], None), ("Тёмная", DARK["bg"], None)]
cw = (W - 48 - 3 * 8) / 4
for i, (cap, c1, c2) in enumerate(themes):
    cx = 24 + i * (cw + 8)
    on = cap == "Сепия"
    sw = b.frame(s, cx, y + 186, cw, 48, "Тема — " + cap, fill=c1, cornerRadius=12, clip=True,
                 stroke=ts["accent"] if on else ts["line"], strokeWeight=2 if on else 1, strokeAlign="inside")
    if c2:
        b.rect(sw, cw / 2, 0, cw / 2, 48, c2)
    else:
        ink = DARK["ink"] if c1 == DARK["bg"] else LIGHT["ink"]
        b.text(sw, 0, 12, "Аа", "book", ink, width=cw, textAlign="center", lineHeight=24)
    b.text(s, cx - 4, y + 242, cap, "caption", ts["ink"] if on else ts["ink2"], width=cw + 8, textAlign="center",
           fontStyle="Medium" if on else "Regular")

# ---- 10 Оглавление
TOC = [(0, "Ионыч", ""), (1, "I", "озвучена"), (1, "II", "озвучена"), (1, "III", ""), (1, "IV", ""), (1, "V", ""),
       (0, "Дама с собачкой", ""), (1, "I", "current"), (1, "II", ""), (1, "III", ""), (1, "IV", ""),
       (0, "Невеста", ""), (1, "I", "")]


def toc_screen(name, downloading):
    s = b.screen(name, t)
    app_bar(s, t, "Оглавление", BOOK, left="close")
    lst = b.frame(s, 0, 85, W, H - 85, "Список глав", clip=True)
    y = 4
    for level, title, mark in TOC:
        cur = mark == "current"
        if cur:
            b.rect(lst, 8, y, W - 16, 48, t["hl"], radius=12, name="Текущая глава")
        role = "title_s" if (cur or level == 0) else "body"
        b.text(lst, 24 + level * 24, y + 13, title, role, t["accent"] if cur else t["ink"], fontFamily=SERIF,
               fontStyle="Bold" if (cur or level == 0) else "Regular", fontSize=16)
        if mark == "озвучена":
            b.icon(lst, W - 24 - 84, y + 15, "check", t["ink2"], size=18)
            b.text(lst, W - 24 - 62, y + 15, "озвучена", "caption", t["ink2"], width=62, textAlign="right")
        y += 48
        if cur:
            x = 48
            if not downloading:
                b.text(lst, x, y + 6, "Не озвучено ≈ 14 мин звука", "caption", t["ink2"])
                button(lst, x, y + 32, None, "Скачать главу · ≈ 0,19 $", t, icon="download", kind="outlined")
                y += 96
            else:
                b.text(lst, x, y + 6, "Озвучиваю: готово 6 из 14 мин", "caption", t["ink"])
                b.rect(lst, x, y + 32, W - x - 24, 4, t["line"], radius=2, name="Доля готового")
                b.rect(lst, x, y + 32, round((W - x - 24) * 6 / 14), 4, t["accent"], radius=2)
                b.text(lst, x, y + 46, "Идёт, пока приложение открыто.", "caption", t["ink2"], width=W - x - 24)
                button(lst, x, y + 70, None, "Остановить", t, icon="stop", kind="outlined")
                y += 134


toc_screen("10 Оглавление", False)
toc_screen("11 Оглавление — скачивание", True)

# ---- 12 Сноска
s = b.screen("12 Сноска", t)
page(s, t, 40, H - 44 - 40, heading="I")
footer(s, t)
y = sheet(s, t, 148)
b.text(s, 24, y + 36, "1", "book_title", t["accent"])
b.text(s, 44, y + 34, NOTE, "book", t["ink"], width=W - 44 - 24)

# ---- 13 Читать отсюда
s = b.screen("13 Читать отсюда", t)
page(s, t, 40, H - 44 - 40, heading="I", highlight=2)
footer(s, t)
# меню над нажатым абзацем: абзац 3 начинается с 18-й строки после заголовка (10 + 7 строк выше, сверено по PNG)
r = centered_row(s, 40 + 4 * LINE + 17 * LINE - 8 - 52, 52, "Меню абзаца")
menu = b.frame(r, 0, 0, 100, 52, "Читать отсюда", fill=t["ink"], cornerRadius=14, layout="horizontal",
               crossAlign="center", gap=10, sizingH="hug", padding=[0, 24, 0, 20],
               effects=[{"type": "dropShadow", "color": "#00000040", "offset": [0, 4], "radius": 12}])
b.icon(menu, 0, 0, "play", t["bg"])
b.text(menu, 0, 0, "Читать отсюда", "body", t["bg"], fontStyle="Medium")

# ---- 14 Слушает
s = b.screen("14 Слушает", t)
listening(s, t)

# ---- 15 Слушает — листаю сам
s = b.screen("15 Слушает — листаю сам", t)
page(s, t, 40, H - PLAYER_H - 8 - 40, paras=LATER + ["Прошла неделя после знакомства."])
player(s, t, "playing")
r = centered_row(s, H - PLAYER_H - 64, 48, "К месту чтения")
f = b.frame(r, 0, 0, 100, 40, "Кнопка «К месту чтения»", fill=t["ink"], cornerRadius=20, layout="horizontal",
            crossAlign="center", gap=8, sizingH="hug", padding=[0, 18, 0, 14],
            effects=[{"type": "dropShadow", "color": "#00000040", "offset": [0, 3], "radius": 10}])
b.icon(f, 0, 0, "locate", t["bg"], size=20)
b.text(f, 0, 0, "К месту чтения", "label", t["bg"])

# ---- 16 Слушает — тёмная
s = b.screen("16 Слушает — тёмная", DARK)
listening(s, DARK)

# ---- 17 Плеер — состояния
s = b.screen("17 Плеер — состояния", t)
b.text(s, 24, 28, "Панель плеера: когда звука нет", "title", t["ink"], width=W - 48)
y = 72
for state, cap, timer in (("preparing", "preparing — ждём первый отрезок", None),
                          ("waiting", "waiting — запас кончился, идут повторы", None),
                          ("paused", "paused — пауза; таймер сна включён", "23 мин")):
    b.text(s, 24, y, cap, "over", t["ink2"])
    player(s, t, state, y0=y + 20, timer=timer, card=True)
    y += 20 + PLAYER_H + 16
b.text(s, 24, y, "stopped — книга закончилась", "over", t["ink2"])
p = b.frame(s, 0, y + 20, W, END_H, "Плеер — конец книги", fill=t["surface"], cornerRadius=16, clip=True)
b.text(p, 16, 16, "Книга закончилась", "title_s", t["ink"], width=W - 16 - 64)
b.text(p, 16, 40, "Чтобы читать глазами, закройте панель.", "caption", t["ink2"], width=W - 16 - 64)
b.icon(p, W - 16 - 24, 16, "close", t["ink2"])

# ---- 18 Плеер — остановка
s = b.screen("18 Плеер — остановка", t)
b.text(s, 24, 28, "Панель плеера: ошибка", "title", t["ink"], width=W - 48)
b.text(s, 24, 58, "Готовый звук доигран; позиция — первый неозвученный абзац.", "caption", t["ink2"],
       width=W - 48)
board = b.frame(s, 0, 112, W, H - 112, "Варианты", layout="vertical", gap=8)
for cap, title, detail, action in (
        ("stopped · 402", "На счёте Gemini закончились деньги", "Google: «prepayment credits are depleted». "
         "После пополнения чтение продолжится с этого абзаца.", ("Пополнить", "open")),
        ("stopped · 404 на модель", "Модель 3.8 Flash больше недоступна",
         "Google: «models/gemini-3.8-flash-tts is not found». Выберите другую модель.", ("Выбрать модель", None)),
        ("stopped · прочие ошибки", "Google отказал в озвучке",
         "«API key not valid. Please pass a valid API key.»", None)):
    capf = b.frame(board, 0, 0, W, 28, "Подпись", layout="horizontal", crossAlign="max", padding=[0, 24, 0, 24])
    b.text(capf, 0, 0, cap, "over", t["ink2"])
    player_stopped(board, t, title, detail, action)

# ---- 19 Скорость
s = b.screen("19 Скорость", t)
listening(s, t)
y = sheet(s, t, 256, "Скорость")
speeds = ["0,75", "1", "1,25", "1,5", "1,75", "2"]
sw = (W - 48 - 2 * 8) / 3
for i, v in enumerate(speeds):
    on = v == "1,25"
    f = b.frame(s, 24 + (i % 3) * (sw + 8), y + 76 + (i // 3) * 56, sw, 48, "Скорость " + v,
                fill=t["accent"] if on else "none",
                cornerRadius=24, stroke="none" if on else t["line"], strokeWeight=1.5, strokeAlign="inside",
                layout="horizontal", mainAlign="center", crossAlign="center")
    b.text(f, 0, 0, v + "×", "label", t["on_accent"] if on else t["ink"])
b.text(s, 24, y + 196, "Меняется только воспроизведение: заново не озвучивается и не стоит денег.", "caption",
       t["ink2"], width=W - 48)

# ---- 20 Таймер сна
s = b.screen("20 Таймер сна", t)
listening(s, t)
y = sheet(s, t, 368, "Таймер сна")
for i, cap in enumerate(("15 минут", "30 минут", "60 минут", "До конца главы", "Выключить")):
    ry = y + 72 + i * 52
    on = i == 3
    if on:
        b.rect(s, 8, ry, W - 16, 52, t["hl"], radius=12, name="Выбрано")
        b.icon(s, W - 24 - 24, ry + 14, "check", t["accent"])
    b.text(s, 24, ry + 15, cap, "body", t["ink"], fontStyle="Medium" if on else "Regular")

# ---- 21 Голос
s = b.screen("21 Голос", t)
app_bar(s, t, "Голос", "для книги «" + BOOK + "»")
lst = b.frame(s, 0, 85, W, H - 85 - 72, "Список голосов", clip=True)


def voice_row(y, name, note, on=False, probe="idle"):
    radio(lst, 18, y + 22, on, t)
    b.text(lst, 56, y + 11, name, "title_s", t["ink"])
    b.text(lst, 56, y + 33, note, "small", t["ink2"], width=W - 56 - 124, maxLines=1)
    if probe is None:
        return
    if probe == "playing":
        f = b.frame(lst, W - 16 - 100, y + 12, 100, 40, "Проба — звучит", fill=t["accent"], cornerRadius=20,
                    layout="horizontal", mainAlign="center", crossAlign="center", gap=6)
        b.icon(f, 0, 0, "stop", t["on_accent"], size=18)
        b.text(f, 0, 0, "Проба", "label", t["on_accent"])
    else:
        f = b.frame(lst, W - 16 - 100, y + 12, 100, 40, "Проба", cornerRadius=20, stroke=t["line"],
                    strokeWeight=1.5, strokeAlign="inside", layout="horizontal", mainAlign="center",
                    crossAlign="center", gap=6)
        b.icon(f, 0, 0, "play", t["accent"], size=18)
        b.text(f, 0, 0, "Проба", "label", t["accent"])


voice_row(4, "Как в настройках", "сейчас Aoede", on=True, probe=None)
b.rect(lst, 16, 72, W - 32, 1, t["line"])
y = 80
b.text(lst, 16, y + 14, "ЖЕНСКИЕ · 14", "over", t["ink2"], letterSpacing="6%")
y += 40
for name, note, probe in (("Achernar", "мягкий", "idle"), ("Aoede", "лёгкий, непринуждённый", "idle"),
                          ("Autonoe", "яркий", "idle"), ("Callirrhoe", "спокойный", "playing"),
                          ("Despina", "плавный", "idle"), ("Erinome", "чёткий", "idle"),
                          ("Gacrux", "зрелый", "idle"), ("Kore", "твёрдый", "idle"), ("Laomedeia", "бодрый", "idle")):
    voice_row(y, name, note, probe=probe)
    y += 64
b.rect(s, 0, H - 72, W, 72, t["surface"], name="Подвал")
b.rect(s, 0, H - 72, W, 1, t["line"])
b.text(s, 16, H - 60, "Проба читает одну и ту же фразу. Стоит меньше цента и оплачивается один раз.",
       "caption", t["ink2"], width=W - 32)


# ---- 22 Настройки
def settings_screen(name, no_key=False):
    s = b.screen(name, t)
    app_bar(s, t, "Настройки")
    y = 85
    def key_link(y):
        f = b.frame(s, 16, y, 200, 48, "Где взять ключ", layout="horizontal", crossAlign="center", gap=6,
                    sizingH="hug")
        b.text(f, 0, 0, "Где взять ключ: aistudio.google.com", "small_m", t["accent"])
        b.icon(f, 0, 0, "open", t["accent"], size=18)

    if no_key:
        note = b.frame(s, 16, y + 16, W - 32, 60, "Пояснение", fill=t["hl"], cornerRadius=12, layout="vertical",
                       padding=[12, 16, 12, 16], sizingV="hug")
        b.text(note, 0, 0, "Чтобы слушать, нужен ключ Gemini. Он вводится один раз и хранится только на "
               "телефоне.", "small", t["ink"], sizingH="fill", textAutoResize="height")
        y += 112
        b.text(s, 16, y + 4, "КЛЮЧ GEMINI", "over", t["accent"], letterSpacing="6%")
        b.rect(s, 16, y + 24, W - 32, 56, t["surface"], radius=8, name="Поле ключа", stroke=t["accent"],
               strokeWeight=2, strokeAlign="inside")
        b.rect(s, 30, y + 40, 2, 24, t["accent"], name="Курсор")
        b.text(s, 38, y + 41, "Вставьте ключ", "body", t["ink2"])
        button(s, W - 16 - 16 - 110, y + 28, 110, "Вставить", t, kind="text", align="max")
        key_link(y + 84)
        y += 140
    else:
        b.text(s, 16, y + 16, "Ключ Gemini", "caption", t["ink2"])
        b.text(s, 16, y + 36, "••••••••••••••••a1f3", "body", t["ink"])
        button(s, W - 16 - 110, y + 23, 110, "Изменить", t, kind="text", align="max")
        key_link(y + 60)
        y += 116
    b.rect(s, 16, y, W - 32, 1, t["line"])

    def row(y, cap, val, chevron=True):
        b.text(s, 16, y + 14, cap, "caption", t["ink2"])
        b.text(s, 16, y + 34, val, "body", t["ink"], width=W - 16 - 56, maxLines=1)
        if chevron:
            b.icon(s, W - 16 - 24, y + 24, "chevron", t["ink2"])
        b.rect(s, 16, y + 72, W - 32, 1, t["line"])

    row(y, "Голос", "Aoede — лёгкий, непринуждённый")
    row(y + 72, "Модель", "3.8 Flash · 0,81 $ за час звука")
    y += 144
    b.text(s, 16, y + 18, "ПОТРАЧЕНО", "over", t["ink2"], letterSpacing="6%")
    spent = (("Ноябрь", "0,00 $"), ("Октябрь", "0,00 $")) if no_key else (("Ноябрь", "4,12 $"), ("Октябрь", "7,80 $"))
    for i, (m, v) in enumerate(spent):
        b.text(s, 16, y + 44 + i * 28, m, "body", t["ink"] if i == 0 else t["ink2"])
        b.text(s, W - 16 - 100, y + 44 + i * 28, v, "body", t["ink"] if i == 0 else t["ink2"], width=100,
               textAlign="right", fontStyle="Medium" if i == 0 else "Regular")
    y += 112
    b.rect(s, 16, y, W - 32, 1, t["line"])
    b.text(s, 16, y + 14, "Озвучка на телефоне", "caption", t["ink2"])
    b.text(s, 16, y + 34, "0 МБ" if no_key else "412 МБ", "body", t["ink"])
    if not no_key:
        button(s, W - 16 - 110, y + 21, 110, "Очистить", t, kind="text", align="max")
        b.text(s, 16, y + 74, "Озвученное второй раз не оплачивается. После очистки его придётся озвучить и "
               "оплатить заново.", "caption", t["ink2"], width=W - 32)
    return s


settings_screen("22 Настройки")
settings_screen("23 Настройки — нет ключа", no_key=True)

# ---- 24 Настройки — модель
s = settings_screen("24 Настройки — модель")
y = sheet(s, t, 336, "Модель")
for i, (name, price, note, on) in enumerate((("3.8 Flash", "0,81 $ за час звука", "по умолчанию", True),
                                             ("3.8 Flash-Lite", "0,54 $ за час звука", "на треть дешевле", False))):
    ry = y + 72 + i * 72
    radio(s, 26, ry + 26, on, t)
    b.text(s, 64, ry + 14, name, "title_s", t["ink"])
    b.text(s, 64, ry + 38, price + " · " + note, "small", t["ink2"])
b.text(s, 24, y + 228, "С 1 января 2027 года Google берёт вдвое больше: 1,62 $ и 1,08 $ за час. Звук одной "
       "модели другой не засчитывается: после смены книги озвучиваются заново.", "caption", t["ink2"],
       width=W - 48)

# ---- 25 Настройки — очистка
s = settings_screen("25 Настройки — очистка")
dialog(s, t, 226, "Очистить озвучку?",
       "Удалится озвучка всех книг — 412 МБ. Слушать уже озвученное снова будет платно.", "Очистить")


# ================================================================ вывод
def contrast(a, c):
    def lum(h):
        r, g, b_ = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
        f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b_)
    l1, l2 = sorted((lum(a), lum(c)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def report_contrast():
    for th in (LIGHT, SEPIA, DARK):
        pairs = [("ink/bg", "ink", "bg"), ("ink2/bg", "ink2", "bg"), ("ink2/surface", "ink2", "surface"),
                 ("accent/bg", "accent", "bg"), ("on_accent/accent", "on_accent", "accent"),
                 ("ink/hl", "ink", "hl")]
        print(th["name"] + ": " + ", ".join("%s %.1f" % (n, contrast(th[a], th[c])) for n, a, c in pairs))


def check(script_path, log_path):
    ids = json.load(open(script_path[:-5] + ".ids.json", encoding="utf-8"))
    bad = 0
    for line in open(log_path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line.startswith("{"):
            continue
        rec = json.loads(line)
        step, want = rec["step"], ids[rec["step"]]
        got = rec.get("result", {}).get("id") if isinstance(rec.get("result"), dict) else None
        if not rec.get("ok"):
            print("step", step, "failed:", rec)
            bad += 1
        elif want is not None and got != want:
            print("step %d: expected id %s, got %s" % (step, want, got))
            bad += 1
    print("ids ok" if not bad else "%d problems" % bad)
    return bad


if __name__ == "__main__":
    if sys.argv[1] == "--check":
        sys.exit(1 if check(sys.argv[2], sys.argv[3]) else 0)
    out = sys.argv[1]
    json.dump(b.steps, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    json.dump(b.ids, open(out[:-5] + ".ids.json", "w", encoding="utf-8"))
    print(len(b.steps), "steps; last id", b.next_id - 1, "; screens", b.n_screens)
    report_contrast()
