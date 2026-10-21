"""Wrap the existing launch artwork in a rounded PDF clipping path."""
from pathlib import Path

from reportlab.pdfgen import canvas


def generate():
    directory = Path(__file__).resolve().parents[1] / (
        'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    )
    output = directory / 'LaunchImage.pdf'
    document = canvas.Canvas(str(output), pagesize=(96, 96), invariant=1)
    document.setTitle('Proxly launch icon')
    document.setAuthor('Proxly')
    # Launch storyboards cannot apply layer.cornerRadius at runtime.
    outline = document.beginPath()
    outline.roundRect(0, 0, 96, 96, 22)
    document.clipPath(outline, stroke=0, fill=0)
    document.drawImage(str(directory / 'LaunchImage@3x.png'), 0, 0, 96, 96)
    document.showPage()
    document.save()
    print(output)


if __name__ == '__main__':
    generate()
