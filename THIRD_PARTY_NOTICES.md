# Third-party notices

The AgentMeter macOS application bundles a Python runtime and the following open-source runtime
components. Versions shown are those used for the 0.1.0 community build.

| Component | Version | License |
| --- | ---: | --- |
| CPython | 3.11.14 | Python Software Foundation License 2.0 |
| AnyIO | 4.14.2 | MIT |
| Bleak | 3.0.2 | MIT |
| Certifi | 2026.7.22 | Mozilla Public License 2.0 |
| h11 | 0.16.0 | MIT |
| HTTPCore | 1.0.9 | BSD 3-Clause |
| HTTPX | 0.28.1 | BSD 3-Clause |
| idna | 3.18 | BSD 3-Clause |
| platformdirs | 4.11.0 | MIT |
| PyObjC | 12.2.1 | MIT |
| pySerial | 3.5 | BSD 3-Clause |
| typing_extensions | 4.16.0 | Python Software Foundation License 2.0 |

PyInstaller 6.21.0 is used to assemble the bundled bridge. Its bootloader is distributed under the
GNU General Public License 2.0 with the PyInstaller Bootloader Exception.

Copyright and complete license terms are available in each upstream distribution:

- [Python](https://docs.python.org/3.11/license.html)
- [AnyIO](https://github.com/agronholm/anyio)
- [Bleak](https://github.com/hbldh/bleak)
- [Certifi](https://github.com/certifi/python-certifi)
- [h11](https://github.com/python-hyper/h11)
- [HTTPCore](https://github.com/encode/httpcore)
- [HTTPX](https://github.com/encode/httpx)
- [idna](https://github.com/kjd/idna)
- [platformdirs](https://github.com/tox-dev/platformdirs)
- [PyObjC](https://github.com/ronaldoussoren/pyobjc)
- [pySerial](https://github.com/pyserial/pyserial)
- [typing_extensions](https://github.com/python/typing_extensions)
- [PyInstaller](https://github.com/pyinstaller/pyinstaller)

## Brand marks

The macOS widgets identify each coding-agent service with that vendor's own mark, redrawn as
vector path data (see `desktop/Widgets/Sources/Components/WidgetProviderMark.swift`). The OpenAI,
Anthropic Claude, Google Gemini, and Cursor marks are trademarks of their respective owners and
are used solely to identify those services. Their use here does not imply any affiliation with or
endorsement by those companies. The Claude, Gemini, and Cursor path data derives from the
[Simple Icons](https://github.com/simple-icons/simple-icons) collection (CC0 1.0); trademark
rights remain with the respective owners.

AgentMeter itself is licensed under the MIT License; see `LICENSE`.
