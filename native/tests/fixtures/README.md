# Metadata fixtures

These files are retained for native codec and metadata tests.

- `jpeg/Portrait_1.jpg` through `Portrait_8.jpg`: `recurser/exif-orientation-examples`, MIT license.
- `png/pngtest.png`: `pnggroup/libpng`, libpng license.
- `webp/test.webp`: `webmproject/libwebp`, BSD 3-Clause license.
Metadata tests inspect headers without decoding pixels. Codec tests exercise
the same JPEG, PNG, and WebP fixtures through the full processing pipeline.
