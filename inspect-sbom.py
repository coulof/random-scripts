#!/usr/bin/env python3
import os
import sys
import json
import argparse
import re
from collections import Counter

def log_error(msg):
    print(f"[ERROR] {msg}", file=sys.stderr)

def log_info(msg):
    print(f"[INFO] {msg}", file=sys.stderr)

def detect_and_parse_sbom(file_path):
    if not os.path.exists(file_path):
        log_error(f"File not found: {file_path}")
        sys.exit(1)
        
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        log_error(f"Invalid JSON format in {file_path}: {e}")
        sys.exit(1)
    except Exception as e:
        log_error(f"Failed to read file {file_path}: {e}")
        sys.exit(1)

    # Auto-detection
    if "spdxVersion" in data:
        return "SPDX 2.0", parse_spdx(data)
    elif data.get("bomFormat") == "CycloneDX":
        return f"CycloneDX {data.get('specVersion', '')}".strip(), parse_cyclonedx(data)
    else:
        # Fallback heuristic checking root keys
        if "packages" in data and isinstance(data["packages"], list):
            return "SPDX (Heuristic)", parse_spdx(data)
        elif "components" in data and isinstance(data["components"], list):
            return "CycloneDX (Heuristic)", parse_cyclonedx(data)
        else:
            log_error("Could not automatically detect SBOM format. Supported formats: SPDX 2.0 and CycloneDX.")
            sys.exit(1)

def parse_spdx(data):
    packages = []
    for pkg in data.get("packages", []):
        name = pkg.get("name")
        if not name:
            continue
        version = pkg.get("versionInfo", "N/A")
        
        # Check both licenseDeclared and licenseConcluded
        license = pkg.get("licenseDeclared")
        if not license or license == "NOASSERTION":
            license = pkg.get("licenseConcluded", "UNKNOWN")
        if license == "NOASSERTION":
            license = "UNKNOWN"
            
        packages.append({
            "name": name,
            "version": version,
            "license": license
        })
    return sorted(packages, key=lambda x: x["name"].lower())

def parse_cyclonedx(data):
    packages = []
    for comp in data.get("components", []):
        name = comp.get("name")
        if not name:
            continue
        version = comp.get("version", "N/A")
        
        # Parse CycloneDX licenses
        license_strings = []
        for lic_entry in comp.get("licenses", []):
            lic = lic_entry.get("license", {})
            lic_id = lic.get("id") or lic.get("name")
            if lic_id:
                license_strings.append(lic_id)
                
        license = " OR ".join(license_strings) if license_strings else "UNKNOWN"
        
        packages.append({
            "name": name,
            "version": version,
            "license": license
        })
    return sorted(packages, key=lambda x: x["name"].lower())

def print_summary(format_name, packages, file_path):
    print("=" * 60)
    print(f"SBOM Summary for: {os.path.basename(file_path)}")
    print(f"Detected Format:  {format_name}")
    print(f"Total Packages:   {len(packages)}")
    print("=" * 60)
    
    if not packages:
        return

    # Count licenses
    licenses = [p["license"] for p in packages]
    license_counts = Counter(licenses)
    
    print("\nTop 10 Package Licenses:")
    print("-" * 45)
    for lic, count in license_counts.most_common(10):
        print(f"  {lic:<35} : {count}")
    print("-" * 45)

def main():
    parser = argparse.ArgumentParser(
        description="Inspect and query package lists and metadata from SPDX and CycloneDX SBOMs."
    )
    parser.add_argument("sbom_file", help="Path to the SPDX or CycloneDX JSON file.")
    parser.add_argument("-p", "--packages", action="store_true", help="List all package names and versions.")
    parser.add_argument("-l", "--licenses", action="store_true", help="List packages alongside their licenses.")
    parser.add_argument("-f", "--filter", help="Case-insensitive regex to filter packages, versions, or licenses.")
    parser.add_argument("-s", "--summary", action="store_true", help="Print summary statistics of the SBOM contents.")
    
    args = parser.parse_args()

    format_name, packages = detect_and_parse_sbom(args.sbom_file)

    # Filter logic
    if args.filter:
        try:
            pattern = re.compile(args.filter, re.IGNORECASE)
        except re.error as e:
            log_error(f"Invalid regular expression: {e}")
            sys.exit(1)
            
        packages = [
            p for p in packages 
            if pattern.search(p["name"]) or pattern.search(p["version"]) or pattern.search(p["license"])
        ]

    # Handle empty packages
    if not packages and not args.summary:
        print("No results found.")
        return

    # Handle requested actions
    if args.summary:
        print_summary(format_name, packages, args.sbom_file)
    elif args.licenses:
        for p in packages:
            print(f"{p['name']} {p['version']} [{p['license']}]")
    elif args.packages or not (args.summary or args.licenses):
        # Default action is listing packages
        for p in packages:
            print(f"{p['name']} {p['version']}")

if __name__ == "__main__":
    main()
