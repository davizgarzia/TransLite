# Changelog - TransLite

## v1.1 - Renamed to TransLite + Visual Translation Effects

### Breaking Changes
- **App renamed from TranslateBar to TransLite**
- Bundle identifier changed from `com.translatebar.app` to `com.translite.app`

### New Features

#### 🎨 Visual Translation Effects
- **HUD flotante elegante** que aparece cerca del texto seleccionado
- **Estados visuales claros:**
  - Traduciendo: Icono de globo giratorio
  - Escribiendo: Indicador de progreso
  - Éxito: Checkmark verde
  - Error: Alerta roja con mensaje
- **Animaciones suaves** de entrada/salida

#### ⚡ Detección Automática de Texto
- **Detección directa** del texto seleccionado usando APIs de Accessibility
- **Obtención de posición** en pantalla del texto seleccionado
- **No requiere copiar** manualmente con Cmd+C

#### ⌨️ Efecto de Escritura Animado
- **Borrado animado** del texto original (letra por letra)
- **Escritura animada** del texto traducido (efecto de mecanografía)
- **Velocidad configurable** (15ms por carácter por defecto)

### Flujo de Trabajo Mejorado

**Antes (v1.0):**
1. Seleccionar texto → Cmd+C → Cmd+Shift+T → Cmd+V

**Ahora (v1.1):**
1. Seleccionar texto → Cmd+Shift+T
2. 🎨 HUD aparece cerca del texto
3. ⚡ Texto se borra con animación
4. ⌨️ Traducción se escribe con efecto typing
5. ✅ Indicador de éxito y el HUD desaparece

### Archivos Nuevos/Modificados

**Nuevos:**
- `TransLiteApp.swift` (renombrado de TranslateBarApp.swift)
- `TransLite.entitlements` (renombrado de TranslateBar.entitlements)
- `TranslationHUDView.swift` - Vista SwiftUI del HUD flotante
- `TranslationHUDController.swift` - Controlador de la ventana flotante
- `CHANGELOG.md` - Este archivo

**Modificados:**
- `AccessibilityHelper.swift` - Añadidas funciones de detección y typing
- `AppViewModel.swift` - Nueva función `translateSelectedText()` con efectos
- `StatusBarController.swift` - Referencias actualizadas a TransLite
- `PopoverView.swift` - Título actualizado a TransLite
- `Info.plist` - Nombre de bundle actualizado
- `project.yml` - Configuración del proyecto actualizada
- `README.md` - Documentación completa actualizada

### Compatibilidad

- ✅ macOS 13.0+
- ✅ Funciona con la mayoría de aplicaciones (Safari, Chrome, TextEdit, VSCode, Slack, etc.)
- ✅ Requiere permisos de Accessibility

### Notas Técnicas

- El HUD usa `.ultraThinMaterial` para efecto glassmorphism nativo
- La detección de texto usa `AXUIElement` APIs de Accessibility
- La animación de escritura usa `CGEvent` para simular teclas
- Posicionamiento del HUD se ajusta automáticamente para no salirse de pantalla

---

## v1.0 - Versión Inicial

### Features
- Traducción de portapapeles con OpenAI API
- Hotkey global (Cmd+Shift+T)
- Auto-paste con permisos de Accessibility
- Almacenamiento seguro de API key en Keychain
- Interfaz de menú bar minimalista
