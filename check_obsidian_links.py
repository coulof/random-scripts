#!/usr/bin/env python3
import os
import re
import sys
import urllib.parse

def parse_frontmatter_aliases(file_path):
    aliases = []
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            # Simple regex to extract YAML frontmatter
            match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
            if match:
                yaml_text = match.group(1)
                for line in yaml_text.splitlines():
                    if line.startswith('aliases:'):
                        # Extract the aliases list or string
                        alias_part = line.split(':', 1)[1].strip()
                        # Handle array format ["Alias1", "Alias2"]
                        if alias_part.startswith('[') and alias_part.endswith(']'):
                            # Strip brackets and split by comma
                            items = alias_part[1:-1].split(',')
                            for item in items:
                                clean_item = item.strip().strip('"').strip("'")
                                if clean_item:
                                    aliases.append(clean_item)
                        else:
                            # Handle single string format
                            clean_item = alias_part.strip('"').strip("'")
                            if clean_item:
                                aliases.append(clean_item)
    except Exception:
        pass
    return aliases

def main():
    if len(sys.argv) > 1:
        vault_root = os.path.abspath(sys.argv[1])
    else:
        vault_root = "~/SUSE/Obsidian/Vault"
        if not os.path.exists(vault_root):
            vault_root = os.getcwd()

    print(f"Scanning Obsidian vault at: {vault_root}")

    all_files = {}  # relative_path_lower -> actual_relative_path
    basename_to_paths = {}  # basename_lower -> list of actual_relative_paths
    alias_to_paths = {}  # alias_lower -> list of actual_relative_paths
    
    # 1. Gather all files and aliases
    for root, dirs, files in os.walk(vault_root):
        dirs[:] = [d for dirs_list in [dirs] for d in dirs_list if not d.startswith('.')]
        
        for file in files:
            if file.startswith('.'):
                continue
            abs_path = os.path.join(root, file)
            rel_path = os.path.relpath(abs_path, vault_root)
            rel_path_lower = rel_path.lower()
            all_files[rel_path_lower] = rel_path
            
            # Map basenames
            basename = os.path.basename(rel_path)
            basename_lower = basename.lower()
            basename_to_paths.setdefault(basename_lower, []).append(rel_path)
            
            basename_no_ext, _ = os.path.splitext(basename)
            basename_no_ext_lower = basename_no_ext.lower()
            basename_to_paths.setdefault(basename_no_ext_lower, []).append(rel_path)

            # Map aliases from frontmatter
            if file.endswith('.md'):
                aliases = parse_frontmatter_aliases(abs_path)
                for alias in aliases:
                    alias_to_paths.setdefault(alias.lower(), []).append(rel_path)

    print(f"Indexed {len(all_files)} files and {len(alias_to_paths)} frontmatter aliases.")

    broken_links = []
    link_pattern = re.compile(r'\[\[(.*?)\]\]')

    # 2. Scan all .md files
    for root, dirs, files in os.walk(vault_root):
        dirs[:] = [d for dirs_list in [dirs] for d in dirs_list if not d.startswith('.')]
        for file in files:
            if not file.endswith('.md'):
                continue
            abs_path = os.path.join(root, file)
            rel_path = os.path.relpath(abs_path, vault_root)
            file_dir = os.path.dirname(rel_path)
            
            with open(abs_path, 'r', encoding='utf-8', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    for match in link_pattern.finditer(line):
                        raw_link = match.group(1).strip()
                        if not raw_link:
                            continue
                        
                        # Handle display name |
                        link_target = raw_link.split('|')[0].strip()
                        
                        # Handle headers/blocks #
                        if '#' in link_target:
                            link_file_part = link_target.split('#')[0].strip()
                        else:
                            link_file_part = link_target
                            
                        if not link_file_part:
                            continue
                            
                        link_file_part_decoded = urllib.parse.unquote(link_file_part)
                        found = False
                        
                        candidates = [
                            link_file_part_decoded,
                            link_file_part_decoded + ".md"
                        ]
                        
                        for candidate in candidates:
                            cand_lower = candidate.lower()
                            
                            # 1. Check relative from current file directory
                            if file_dir:
                                rel_from_curr = os.path.normpath(os.path.join(file_dir, candidate))
                                if rel_from_curr.lower() in all_files:
                                    found = True
                                    break
                                    
                            # 2. Check as absolute relative path from vault root
                            if cand_lower in all_files:
                                found = True
                                break
                                
                            # 3. Check by basename
                            base_cand = os.path.basename(candidate)
                            base_cand_lower = base_cand.lower()
                            if base_cand_lower in basename_to_paths:
                                found = True
                                break
                                
                            # 4. Check frontmatter aliases
                            if cand_lower in alias_to_paths:
                                found = True
                                break

                        if not found:
                            broken_links.append({
                                'source_file': rel_path,
                                'line_number': line_num,
                                'raw_link': f"[[{raw_link}]]",
                                'target': link_file_part_decoded
                            })

    # 3. Output results
    if not broken_links:
        print("\nSUCCESS: No broken links found!")
    else:
        print(f"\nFOUND {len(broken_links)} BROKEN LINKS:")
        for idx, bl in enumerate(broken_links, 1):
            print(f"{idx:3d}. {bl['source_file']}:{bl['line_number']} -> {bl['raw_link']} (Target '{bl['target']}' not found)")

if __name__ == "__main__":
    main()
