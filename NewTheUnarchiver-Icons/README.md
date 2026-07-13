# NewTheUnarchiver — App Icon

Готовый к установке набор иконок (macOS / Windows / Linux) + векторный исходник.
Знак: неоновая стрелка-извлечение из data-сегментов над светящимся архивным ящиком.

## Структура

```
NewTheUnarchiver-Icons/
├── source/
│   ├── icon.svg                 ← ВЕКТОРНЫЙ ИСХОДНИК (правьте здесь, viewBox 1024)
│   └── icon-simple.svg          ← упрощённый знак для мелких размеров
│
├── AppIcon.icns                 ← macOS: готовый бинарь
├── AppIcon.iconset/             ← macOS: 10 PNG для `iconutil -c icns`
├── AppIcon.appiconset/          ← Xcode (классический, все размеры) — надёжный вариант
├── AppIcon-Appearances.appiconset/  ← Xcode 16/26: один 1024 + Any / Dark / Tinted
├── iconcomposer/                ← плоское 1024-артворк (Default/Dark/Tinted) для Icon Composer
│
├── windows/newtheunarchiver.ico ← Windows: мультиразмерный .ico (16…256)
├── linux/                       ← Linux: hicolor PNG (16…512) + .desktop
│
├── png/                         ← сырые PNG: 16/24/32/48/64/128/256/512/1024
├── appearances/                 ← dark/ и tinted/ PNG (1024…128)
└── README.md
```

Все PNG отрисованы из вектора (1024 — нативный, без апскейла), squircle macOS 26,
прозрачные углы, паддинг и мягкая тень. До 32 px — упрощённый знак.

---

## macOS

**Готовый .icns** → положите `AppIcon.icns` в `YourApp.app/Contents/Resources/`,
в `Info.plist`: `CFBundleIconFile = AppIcon`.

**Xcode (классика)** → перетащите `AppIcon.appiconset` в `Assets.xcassets`.

**Xcode 16 / 26 с оттенками (Any / Dark / Tinted)** → перетащите
`AppIcon-Appearances.appiconset` в `Assets.xcassets`. Внутри один 1024-знак и
автоматические тёмный + подкрашенный варианты.

**Icon Composer (новый формат `.icon`, macOS 26 «Liquid Glass»)**
1. Откройте Icon Composer → New.
2. Импортируйте `iconcomposer/artwork-1024.png` как основной слой
   (а `*-dark.png` / `*-tinted.png` — для соответствующих режимов).
3. Сохраните как `AppIcon.icon` и добавьте в проект.
   (Сам `.icon` — проприетарный бандл Apple, поэтому отдаю готовое 1024-артворк
   для импорта; собрать `.icon` можно только в Icon Composer.)

**Пересборка .icns вручную:** `iconutil -c icns AppIcon.iconset -o AppIcon.icns`

## Windows
`windows/newtheunarchiver.ico` — мультиразмерный (16/24/32/48/64/128/256).
- Visual Studio: добавьте .ico в ресурсы / `App.ico`.
- Tauri: `src-tauri/icons/icon.ico`. Electron-builder: `build.win.icon`.

## Linux
`linux/` повторяет дерево темы **hicolor**:
```
sudo cp -r linux/16x16 … linux/512x512  /usr/share/icons/hicolor/
sudo cp linux/newtheunarchiver.desktop  /usr/share/applications/
sudo gtk-update-icon-cache /usr/share/icons/hicolor
```
(имя иконки в .desktop — `newtheunarchiver`)

---

## Векторный исходник
`source/icon.svg` — единственный мастер. Поменяли что-то в нём → перегенерируйте
все растровые наборы из него. Цвета: Graphite #2B2F37→#0F1115, Mint #54E6A8,
Kraft #B5732A→#794916.
