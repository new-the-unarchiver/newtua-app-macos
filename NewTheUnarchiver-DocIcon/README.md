# NewTheUnarchiver — Document Icon

Иконка файла-архива: белый лист с загнутым углом и знаком приложения.
Назначается типам файлов (.zip / .7z / .rar / .tar.gz …), которые открывает
NewTheUnarchiver. Без впечатанного расширения — базовый знак («маска»),
поверх которого macOS сам рисует бейдж расширения.

## Структура
```
NewTheUnarchiver-DocIcon/
├── source/docicon.svg        ← векторный исходник (viewBox 1024)
├── DocumentIcon.icns         ← готовый бинарь
├── DocumentIcon.iconset/     ← 10 PNG для `iconutil -c icns`
├── png/                      ← docicon_16 … docicon_1024
└── README.md
```

## Как назначить типу файла (macOS)
1. Положите `DocumentIcon.icns` в `YourApp.app/Contents/Resources/`.
2. В `Info.plist` приложения опишите тип документа и сошлитесь на иконку:
   ```xml
   <key>CFBundleDocumentTypes</key>
   <array>
     <dict>
       <key>CFBundleTypeName</key><string>Archive</string>
       <key>CFBundleTypeIconFile</key><string>DocumentIcon</string>
       <key>LSItemContentTypes</key>
       <array>
         <string>public.zip-archive</string>
         <string>org.7-zip.7-zip-archive</string>
         <string>com.rarlab.rar-archive</string>
         <string>public.tar-archive</string>
       </array>
       <key>CFBundleTypeRole</key><string>Viewer</string>
     </dict>
   </array>
   ```
3. (Современный путь) В Xcode добавьте **Exported/Imported Type Identifier**
   и укажите `DocumentIcon` как иконку типа — либо перетащите PNG из `png/`
   в соответствующий слот в Icon Composer.

## Пересборка из вектора
Правьте `source/docicon.svg` → перегенерируйте PNG/.icns.
`iconutil -c icns DocumentIcon.iconset -o DocumentIcon.icns`
