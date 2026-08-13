#!/usr/bin/env python3
"""Gera um APK reduzido contendo apenas o que o monodroid precisa ler por mmap.

O ScourgeBringer guarda o assembly store dentro do proprio APK
(``assemblies/assemblies.blob`` + o blob por arquitetura). O monodroid abre os
APKs de ``runtimeApks``, varre o diretorio central e exige que as entradas de
``assemblies/`` estejam STORED. Copiar o APK inteiro (154 MB) para o aparelho so
para ler 5 MB de assemblies e desperdicio, entao aqui reescrevemos um zip minimo
com as mesmas entradas, STORED e com o inicio dos dados alinhado (16 KiB cobre
qualquer exigencia de pagina do runtime).
"""
import os
import struct
import sys
import zipfile

ALIGN = 16384
KEEP_PREFIXES = ("assemblies/",)
KEEP_NAMES = ("AndroidManifest.xml",)


def build(src_apk, dst_apk):
    entries = []
    with zipfile.ZipFile(src_apk) as z:
        for info in z.infolist():
            if info.filename.startswith(KEEP_PREFIXES) or info.filename in KEEP_NAMES:
                entries.append((info.filename, z.read(info.filename)))
    if not entries:
        raise SystemExit("nenhuma entrada assemblies/ encontrada em %s" % src_apk)

    out = open(dst_apk, "wb")
    central = []
    for name, data in entries:
        nb = name.encode("utf-8")
        local_header_len = 30 + len(nb)
        offset = out.tell()
        pad = (-(offset + local_header_len)) % ALIGN
        extra = b"\0" * pad
        crc = zipfile.crc32(data) & 0xFFFFFFFF
        out.write(struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, 0, 0, 0,
                              crc, len(data), len(data), len(nb), len(extra)))
        out.write(nb)
        out.write(extra)
        data_off = out.tell()
        assert data_off % ALIGN == 0, (name, data_off)
        out.write(data)
        central.append((nb, crc, len(data), offset))

    cd_start = out.tell()
    for nb, crc, size, offset in central:
        out.write(struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0, 0, 0, 0,
                              crc, size, size, len(nb), 0, 0, 0, 0, 0, offset))
        out.write(nb)
    cd_size = out.tell() - cd_start
    out.write(struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(central), len(central),
                          cd_size, cd_start, 0))
    out.close()

    with zipfile.ZipFile(dst_apk) as z:
        bad = z.testzip()
        if bad:
            raise SystemExit("zip invalido: %s" % bad)
        for info in z.infolist():
            print("  %-40s %9d bytes  compress=%d" %
                  (info.filename, info.file_size, info.compress_type))
    print("OK: %s (%d bytes)" % (dst_apk, os.path.getsize(dst_apk)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("uso: make_assembly_apk.py <apk-original> <apk-saida>")
    build(sys.argv[1], sys.argv[2])
