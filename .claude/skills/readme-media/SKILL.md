---
name: readme-media
description: How the README's screenshots and demo GIF work — theme-aware picture pairs hotlinked from ninerlog.com — and how to regenerate or extend them. Load when changing README images, adding a screenshot for a new feature, or updating the feature list.
---

# README media

The README's images are captures of the real app, hosted by the website repo
and hotlinked as `https://ninerlog.com/images/<name>`. Each one is a
light/dark pair that follows the reader's GitHub theme:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://ninerlog.com/images/feature-x-dark.png">
  <img alt="…" src="https://ninerlog.com/images/feature-x.png">
</picture>
```

GitHub supports `<picture>` in Markdown; the animated Quick Log demo uses the
same pattern with `demo-quicklog[-dark].gif`.

## Regenerating or adding an image

Nothing is edited here — media is produced in `ninerlog-frontend` and
published through `ninerlog-website`:

1. In `../ninerlog-frontend`: `npm run shots:marketing` (see its
   `marketing-images` skill — targets, the "famous women in aviation" story
   fixtures, review checklist).
2. Copy the outputs into `../ninerlog-website/images/` and ship that repo —
   ninerlog.com serves them.
3. Reference the pair here with the `<picture>` pattern above. Use existing
   basenames; a rename breaks this README until the website deploys.

## Keeping the feature list honest

The README's Features section mirrors https://ninerlog.com/features
(`src/pages/features.njk` in the website repo). When features land there,
fold them in here — same order of sections, terser wording. The README
should never advertise less than the website, and never more than the app.
