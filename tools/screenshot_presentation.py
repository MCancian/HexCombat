"""Export docs/presentation.html to a PDF, one slide per page.

On screen the deck is a horizontal filmstrip (each .slide is 100vw, navigation
scrolls the container with translateX). That layout never paginates, so a naive
print produced one giant page. The deck now carries an @media print block that
un-does the filmstrip and lays each slide on its own 1920x1080 page, plus
window.__fitSlidesForPrint() which scales down any slide that would otherwise
overrun the page (e.g. the logistics heatmap). We render with Chromium's native
PDF engine so text/SVG stay vector-crisp rather than being raster screenshots.
"""
from playwright.sync_api import sync_playwright
import os


def main():
    html_path = os.path.abspath('docs/presentation.html')
    pdf_path = os.path.abspath('docs/presentation_slides.pdf')

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        page.goto(f"file://{html_path}")

        # Let webfonts and images settle before measuring/printing.
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1500)

        # page.pdf() forces the print media type; emulate it now so the fit pass
        # measures against the print layout (each slide fixed at 1080px).
        page.emulate_media(media="print")
        page.evaluate("window.__fitSlidesForPrint && window.__fitSlidesForPrint()")

        page.pdf(
            path=pdf_path,
            width="1920px",
            height="1080px",
            print_background=True,
            margin={"top": "0", "bottom": "0", "left": "0", "right": "0"},
        )

        browser.close()

    print(f"Saved to {pdf_path}")


if __name__ == '__main__':
    main()
