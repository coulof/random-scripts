#!/usr/bin/env python3
import os
import re
import sys

def main():
    # Allow overriding the vault path via command line argument
    if len(sys.argv) > 1:
        vault_root = os.path.abspath(sys.argv[1])
    else:
        vault_root = "~/SUSE/Obsidian/Vault"
        if not os.path.exists(vault_root):
            vault_root = os.getcwd()

    print(f"Auditing mixed-bracket links at: {vault_root}")

    all_files = []
    for root, dirs, files in os.walk(vault_root):
        dirs[:] = [d for dirs_list in [dirs] for d in dirs_list if not d.startswith('.')]
        for file in files:
            if file.endswith('.md'):
                all_files.append(os.path.join(root, file))

    # Regex to match mixed-bracket links of the form [[text](url)]
    mixed_pattern = re.compile(r'\[\[([^\]\n]+?)\]\(([^)\n]+?)\)\]')
    
    findings = []
    
    for file_path in all_files:
        rel_path = os.path.relpath(file_path, vault_root)
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                for match in mixed_pattern.finditer(line):
                    findings.append({
                        'file': rel_path,
                        'line': line_num,
                        'full_match': match.group(0),
                        'text': match.group(1),
                        'url': match.group(2)
                    })

    if not findings:
        print("\nSUCCESS: No mixed-bracket link typos found!")
    else:
        print(f"\nFOUND {len(findings)} MIXED-BRACKET LINK TYPOS:")
        for idx, f in enumerate(findings, 1):
            print(f"{idx:3d}. {f['file']}:{f['line']} -> {f['full_match']} (Text: '{f['text']}', URL: '{f['url']}')")

if __name__ == "__main__":
    main()
