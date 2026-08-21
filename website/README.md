# Astro Starter Kit: Minimal

```sh
npm create astro@latest
```

[![Astro](https://img.shields.io/static/v1?label=Made%20by&message=Astro&style=flat-square&color=%23ff4d2e&logo=astro&logoColor=white)](https://astro.build/) [![Astro version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fwithastro%2Fcreate-astro%2Fmain%2Ftemplates%2Fminimal%2Fpackage.json&query=%24.version&label=astro%20&style=flat-square&color=%230d1117)](https://github.com/withastro/create-astro/blob/main/templates/minimal/package.json) [![GitHub contributors](https://img.shields.io/github/contributors/withastro/create-astro?style=flat-square&color=%230d1117)](https://github.com/withastro/create-astro/graphs/contributors)

This is Astro's minimal, bare-bones starter template. No opinions about what kind of frontend code you want to write — just the basics baked in.

Want to get a head start? Check out [Astro examples](https://astro.build/examples) instead.

## 🚀 Project Structure

Astro looks at your `src/pages` directory to build your site (routes). Each page auto-detects the appropriate renderer based on its file extension.

```
src/
  pages/
    index.astro
  styles/
    global.css
```

## 🚀 Deploy to GitHub Pages

This site is configured to deploy as a GitHub Pages **project/site page** at
`https://<your-username>.github.io/AestheticOS/`.

1. Push this repository to GitHub (repo named `AestheticOS`).
2. Go to **Settings → Pages** and set **Source** to **GitHub Actions**.
3. On every push to `main`, the `.github/workflows/pages.yml` workflow builds
   the site and publishes it automatically.

> The Astro `base` is set to `/AestheticOS/` in `astro.config.mjs`, which is
> required for project/site pages. If you ever change the repo name, update it
> there too.

## 🧭 Commands

All commands are run from the root of the project, from a terminal:

| Command             | Action                                            |
| :------------------ | :------------------------------------------------ |
| `npm install`       | Installs dependencies                             |
| `npm run dev`       | Starts local dev server at `localhost:4321`       |
| `npm run build`     | Build your production site to `./dist/`           |
| `npm run preview`   | Preview your build locally, before deploying      |
| `npm run astro ...` | Run CLI commands like `astro add`, `astro check`  |

## ✎ Edit Locally

```sh
npm run dev
```

To exit the dev server, hit `Ctrl + C` at any time.

### Learn more on [the Astro Documentation website](https://docs.astro.build)
