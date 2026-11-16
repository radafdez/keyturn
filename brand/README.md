# Brand

The Keyturn symbol: two arrows going round a bolt, the account switching
over. Every file is a plain SVG with no text, fonts, scripts or embedded images.

| Folder | What is in it |
|--------|---------------|
| `logos/` | The round badge (`logo-*`), and the bare symbol for light and dark bars (`navbar-*`) |
| `isotypes/` | The bare symbol for light and dark backgrounds, and on a round or square badge |
| `app-icons/` | Square and rounded tiles, 180 to 1024 px |
| `favicons/` | 16, 32 and 48 px, on a tile or transparent for light or dark themes; the 16 px ones have heavier strokes |
| `mono/` | One colour: dark, white, green |

The app's own icons are drawn from the same geometry by
[`scripts/make-icon.swift`](../scripts/make-icon.swift), which places the
symbol on the macOS icon grid; the `app-icons/` here fill the whole canvas.

| Colour | Hex |
|--------|-----|
| Green | `#48BE96` |
| Silver (upper arrow on dark) | `#D9DAE0` |
| Charcoal (upper arrow on light) | `#303640` |
| Tile | `#2D323D` → `#272C36` |
| Ink (one colour) | `#0E0E10` |

Keep the proportions and don't recolour the two-colour versions. The symbol is
the project's own. It is not the Supabase logo, and it should not be shown next
to the Supabase logo in a way that suggests the app comes from Supabase.

---

## Español

El símbolo de Keyturn: dos flechas que giran alrededor de un rayo, la
cuenta que cambia. Todos los ficheros son SVG sin texto, fuentes, scripts ni
imágenes incrustadas. Los iconos de la app salen de la misma geometría con
`scripts/make-icon.swift`, que coloca el símbolo en la rejilla de iconos de
macOS. Mantén las proporciones y no cambies los colores de las versiones
bicolores. El símbolo es del proyecto; no es el logo de Supabase, y no debe
ponerse junto a él como si la app fuera de Supabase.
