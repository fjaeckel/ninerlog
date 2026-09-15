# Terms of Service & Privacy Policy

If you run NinerLog for other people — a flying club, a school, a group of
friends — you may want, or be required, to show them a Terms of Service and a
Privacy Policy. NinerLog ships neither: they are yours to write. Once you
provide them, the frontend links them from the login and registration screens,
the sidebar and the mobile menu, and the registration form tells new users that
creating an account means agreeing to them.

Nothing appears until you add a file, so an instance without documents is
unchanged.

## Setup

1. Create a `legal/` folder next to `docker-compose.yml` (or point `LEGAL_PATH`
   in `.env` somewhere else). It is gitignored, so your documents stay out of
   this repository's history.

2. Write your documents as Markdown:

   | File | Document |
   |------|----------|
   | `legal/terms.md` | Terms of Service |
   | `legal/privacy.md` | Privacy Policy |

   Either file on its own is fine. GitHub-flavoured Markdown is supported:
   headings, lists, tables, links, emphasis. Start with a `# Title` heading —
   the page uses it as the document's heading.

3. Restart the frontend so it picks up which files exist:

   ```bash
   docker compose up -d frontend
   ```

   The container log confirms it:

   ```
   Legal documents published: terms,privacy
   ```

The documents are now at `https://your-domain/legal/terms` and
`https://your-domain/legal/privacy`.

## Translations

NinerLog's UI is available in English and German. To show a document in the
user's language, add a file with the language code before the extension:

| File | Served to |
|------|-----------|
| `legal/terms.md` | Everyone, unless a better match exists |
| `legal/terms.de.md` | Users with the UI set to German |
| `legal/privacy.md`, `legal/privacy.de.md` | Same for the Privacy Policy |

The un-suffixed file is the fallback and must exist for the document to be
published at all.

## Editing

Edits to an existing file show up on the next page load — the files are served
uncached, no restart needed. Adding or removing a file changes which links the
app shows, so that does need `docker compose up -d frontend`.

## Overriding the detection

The frontend publishes whatever files it finds. If you want to mount the folder
but publish only some of it, set `VITE_LEGAL_DOCS` in `.env` to the documents
you want (`terms`, `privacy` or `terms,privacy`). Leave it empty to go back to
detection.

## What this does not do

NinerLog does not record acceptance: there is no checkbox and no timestamp per
user. The registration form states that creating an account means agreeing to
the published documents, which is enough for many operators — check your own
requirements. Existing users are not asked to re-accept a changed document; if
you need that, announce it through the admin console's announcements.
