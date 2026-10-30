# Design system

Scope: **design tokens and the theme they generate.** No component library.

That is a deliberate boundary. A component library is a permanent maintenance
commitment and a source of friction the first time a design does not fit one of
its widgets; a token pipeline is neither, and it is the part that actually
stops a hex code being pasted into a widget. Components can be added per
project on top of the generated theme.

```
design/tokens.json  ──►  make design-tokens  ──►  lib/generated/design_tokens.g.dart
```

## The token file

JSON rather than YAML because this is what design tools export — Token Studio,
Style Dictionary and the Figma API all emit JSON, so an export drops in without
a conversion step.

```json
{
  "font": { "family": "Inter" },

  "color": {
    "primary":    { "light": "#4F46E5", "dark": "#818CF8" },
    "on_primary": { "light": "#FFFFFF", "dark": "#1E1B4B" },
    "brand_accent": "#F43F5E"
  },

  "spacing":    { "xs": 4, "sm": 8, "md": 16, "lg": 24 },
  "radius":     { "sm": 4, "md": 8, "pill": 999 },
  "typography": {
    "body_large": { "size": 16, "weight": 400, "height": 1.5 }
  }
}
```

Colours accept `#RGB`, `#RRGGBB` or `#AARRGGBB`. A bare string means the same
value in both modes — right for brand colours and anything deliberately not
themed.

### Required colour roles

`primary`, `on_primary`, `secondary`, `on_secondary`, `surface`, `on_surface`,
`error`, `on_error` are **required**, and their absence is a validation error.

They map onto Flutter's `ColorScheme`. Without a real `ColorScheme`, every
stock Material widget keeps its default blue and the token file only colours
the handful of widgets that read the extension directly — which is exactly how
a design system ends up half-applied.

Roles the file does not name (containers, inverse surfaces, scrims) are derived
from `primary` via `ColorScheme.fromSeed`, then the named roles are pinned on
top. The alternative is enumerating all thirty-odd Material roles by hand, and
nobody maintains that.

### `height` is a multiplier

Flutter's `TextStyle.height` is a multiple of font size, not pixels. A design
tool exporting `lineHeight: 24` for a 16px font means `1.5` here. The validator
**warns** when `height` exceeds 10, because the result of getting this wrong is
a layout that is technically valid and visibly wrong.

## Using the theme

```dart
MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
);
```

```dart
Container(
  padding: EdgeInsets.all(context.spacing.md),
  decoration: BoxDecoration(
    color: context.colors.surface,
    borderRadius: BorderRadius.circular(context.radii.md),
  ),
  child: Text('Hello', style: context.typography.bodyLarge),
);
```

Tokens are registered as `ThemeExtension`s rather than exposed as globals, so
they follow the ambient theme. A subtree can be re-themed, and a widget test
can override them, neither of which works with `AppColors.primary` as a static.

Typography tokens named after a Material slot (`body_large`, `title_medium`,
`display_large`, …) are also wired into the `TextTheme`, so stock widgets pick
them up without every call site reaching for the extension.

Type styles carry no colour — it comes from the `ColorScheme` at use time, so
one scale serves both modes instead of being duplicated per mode.

## Generated code is committed

`lib/generated/design_tokens.g.dart` is in the repo, so a fresh checkout builds
without running the generator. Both buildspecs run `scripts/codegen.sh check`,
which fails the build if the generated file no longer matches its source —
otherwise a token edit without a regeneration compiles the *old* theme and
everything passes, which is the failure mode that wastes an afternoon.

## What is not here, and what it would take

- **Components.** Add them in the project, on top of `context.colors` and
  `context.spacing`.
- **Golden tests.** The natural next step once components exist: render each
  component in both modes and fail the build on a pixel diff. Not useful
  without components to render.
- **Figma sync.** `design/tokens.json` is the shape a Token Studio export
  already has, so syncing is a fetch step writing that file, plus a Figma token
  in Secrets Manager. Deliberately not wired up — it couples the platform to
  one team's Figma setup.
- **Per-brand theming.** The generator emits one `AppColors`. Multiple brands
  would mean one token file per brand and a generated class per brand; the
  `ThemeExtension` shape already supports swapping them at runtime.
