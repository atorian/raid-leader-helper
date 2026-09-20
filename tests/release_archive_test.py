#!/usr/bin/env python3

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]


class ReleaseArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("Makefile", "RLHelper.toc", "RLHelper.xml", "Core.lua"):
            shutil.copy2(ROOT / name, self.root / name)
        for name in ("modules", "lib", "Libs", "data", "scripts"):
            if (ROOT / name).exists():
                shutil.copytree(ROOT / name, self.root / name)

    def build(self):
        return subprocess.run(
            ["make", "release"], cwd=self.root, capture_output=True, text=True
        )

    def test_clean_build_contains_boss_data_and_nested_libraries(self):
        result = self.build()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        with ZipFile(self.root / "RLHelper.zip") as archive:
            self.assertEqual(
                (self.root / "data/BossIds.lua").read_bytes(),
                archive.read("RLHelper/data/BossIds.lua"),
            )
            self.assertIn(
                "RLHelper/Libs/LibCompat-1.0/Libs/LibGroupTalents-1.0/LibTalentQuery-1.0.lua",
                archive.namelist(),
            )
            self.assertTrue(all(name.startswith("RLHelper/") for name in archive.namelist()))

    def test_old_staging_files_and_archive_entries_are_not_reused(self):
        stale = self.root / "release/RLHelper/stale.lua"
        stale.parent.mkdir(parents=True)
        stale.write_text("stale")
        with ZipFile(self.root / "RLHelper.zip", "w") as archive:
            archive.writestr("RLHelper/removed.lua", "removed")
        result = self.build()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        with ZipFile(self.root / "RLHelper.zip") as archive:
            self.assertNotIn("RLHelper/stale.lua", archive.namelist())
            self.assertNotIn("RLHelper/removed.lua", archive.namelist())

    def test_missing_toc_reference_fails_even_if_present_in_old_release(self):
        with (self.root / "RLHelper.toc").open("a") as toc:
            toc.write("\nmodules\\Missing.lua\n")
        stale = self.root / "release/RLHelper/modules/Missing.lua"
        stale.parent.mkdir(parents=True)
        stale.write_text("stale")
        result = self.build()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("modules/Missing.lua", result.stderr)
        self.assertFalse((self.root / "RLHelper.zip").exists())

    def test_reference_present_in_source_but_not_archive_fails(self):
        (self.root / "Unpackaged.lua").write_text("-- not copied into the release")
        with (self.root / "RLHelper.toc").open("a") as toc:
            toc.write("\nUnpackaged.lua\n")
        result = self.build()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Unpackaged.lua", result.stderr)
        self.assertFalse((self.root / "RLHelper.zip").exists())

    def test_missing_nested_xml_or_script_fails_without_replacing_archive(self):
        for name in (
            "Libs/LibCompat-1.0/Libs/LibGroupTalents-1.0/lib.xml",
            "Libs/LibCompat-1.0/Libs/LibGroupTalents-1.0/LibTalentQuery-1.0.lua",
        ):
            with self.subTest(name=name):
                target = self.root / name
                original = target.read_bytes()
                target.unlink()
                archive = self.root / "RLHelper.zip"
                with ZipFile(archive, "w") as previous:
                    previous.writestr("RLHelper/previous.lua", "previous release")
                previous_archive = archive.read_bytes()
                result = self.build()
                self.assertNotEqual(0, result.returncode)
                self.assertIn(name, result.stderr)
                self.assertEqual(previous_archive, archive.read_bytes())
                target.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
