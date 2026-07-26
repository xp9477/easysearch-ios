#!/usr/bin/env python3
"""Register Swift files in project.pbxproj (app target A4000000 or tests 35562CF8C17B7D497379E492)."""
import sys, re, hashlib, pathlib

PBX = pathlib.Path("EasySearch.xcodeproj/project.pbxproj")

def make_id(path, suffix):
    digest = hashlib.md5((path + suffix).encode()).hexdigest().upper()[:24]
    return digest

def add_file(text, filepath, group_marker, sources_marker):
    name = filepath.split("/")[-1]
    file_id = make_id(filepath, "ref")
    build_id = make_id(filepath, "build")
    if file_id in text:
        print(f"skip (exists): {filepath}")
        return text
    # 1. PBXBuildFile
    build_line = f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};\n"
    anchor = "/* Begin PBXBuildFile section */\n"
    text = text.replace(anchor, anchor + build_line, 1)
    # 2. PBXFileReference
    ref_line = (f"\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; includeInIndex = 1; "
                f"lastKnownFileType = sourcecode.swift; name = {name}; path = {filepath}; sourceTree = SOURCE_ROOT; }};\n")
    anchor = "/* Begin PBXFileReference section */\n"
    text = text.replace(anchor, anchor + ref_line, 1)
    # 3. group children
    pattern = re.compile(re.escape(group_marker))
    m = pattern.search(text)
    assert m, f"group marker not found: {group_marker}"
    insert_at = m.end()
    text = text[:insert_at] + f"\t\t\t\t{file_id} /* {name} */,\n" + text[insert_at:]
    # 4. sources build phase
    m2 = re.search(re.escape(sources_marker), text)
    assert m2, f"sources marker not found: {sources_marker}"
    insert_at = m2.end()
    text = text[:insert_at] + f"\t\t\t\t{build_id} /* {name} in Sources */,\n" + text[insert_at:]
    print(f"added: {filepath}")
    return text

if __name__ == "__main__":
    # usage: add_pbx_file.py <filepath> <group_marker> [app|tests]
    filepath, group_marker = sys.argv[1], sys.argv[2]
    target = sys.argv[3] if len(sys.argv) > 3 else "app"
    sources = {
        "app": "A4000000 /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n",
        "tests": "35562CF8C17B7D497379E492 /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n",
    }[target]
    text = PBX.read_text()
    text = add_file(text, filepath, group_marker, sources)
    PBX.write_text(text)
