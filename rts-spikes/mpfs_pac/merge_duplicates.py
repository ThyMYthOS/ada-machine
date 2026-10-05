#!/usr/bin/env python3

import sys
import os
import re


def find_generic_name_from_prefix(prefix):
    """Derive generic name from prefix."""
    # For mpfs_mss-svd-can -> CAN_Peripheral
    # We need to extract the part that represents the generic name

    # Split by dashes and take the last part
    name = prefix.split('-')[-1]
    return f"{name}_Peripheral"

def replace_peripheral_type(line, generic_name):
    """Replace specific peripheral type with generic one."""
    # Example: CAN_A_HI_Periph : aliased CAN_A_HI_Peripheral with Import, Address => CAN_A_HI_Base;
    # Should become: CAN_A_HI_Periph : aliased CAN_Peripheral with Import, Address => CAN_A_HI_Base;

    # Find the pattern and replace the peripheral type
    pattern = r'(\w+)\s*:\s*aliased\s+(\w+)_Peripheral'
    replacement = f'\\1 : aliased {generic_name}'

    return re.sub(pattern, replacement, line)

def merge_files():
    """Main function to merge files with peripheral instantiations."""
    if len(sys.argv) < 2:
        print("Usage: python3 merge_files.py <file1> <file2> ...")
        return

    ads_files = sys.argv[1:]

    # Get basenames for common prefix calculation
    basenames = [os.path.basename(f) for f in ads_files]
    dir = os.path.dirname(ads_files[0])

    # Find common prefix
    common_prefix = os.path.commonprefix(basenames).strip("_")
    first_file_postfix = basenames[0].split('.')[0].removeprefix(common_prefix)

    # If common prefix is empty, try to find a better one
    if not common_prefix:
        print("No common prefix found. Please provide a more specific directory structure.")
        exit(-1)
    else:
        print(f"Common prefix: {common_prefix}")

    # Find generic name for peripherals
    generic_name = find_generic_name_from_prefix(common_prefix)

    # Read all files and extract instantiations. The OUTPUT body is taken
    # from ads_files[0] below, so the line index we splice at must be
    # ads_files[0]'s own instantiation line -- not whichever file happens
    # to be last in the loop, which may put its instantiation at a
    # different line number and silently corrupt the merge.
    all_instantiations = []
    first_file_instantiation_line = None

    for file_index, file_path in enumerate(ads_files):
        with open(file_path, 'r') as f:
            content = f.read()

        # Extract instantiation lines
        lines = content.split('\n')
        for i, line in enumerate(lines):
            if 'aliased' in line and 'Peripheral' in line:
                # This looks like an instantiation line
                match = re.search(r'(\w+)\s*:\s*aliased\s+(\w+)_Peripheral', line)
                if match:
                    # Replace the specific peripheral with generic one
                    modified_line = replace_peripheral_type(line, generic_name)
                    all_instantiations.append(lines[i-1] + '\n' + modified_line + '\n' + lines[i+1])
                    if file_index == 0:
                        first_file_instantiation_line = i

    if first_file_instantiation_line is None:
        print(f"No peripheral instantiation found in {ads_files[0]}; nothing to anchor the merge on.")
        exit(-1)

    # Write the output file
    output_file = os.path.join(dir, f"{common_prefix}.ads")
    with open(output_file, 'w') as f:
        replacer = re.compile(re.escape(first_file_postfix), re.IGNORECASE)
        with open(ads_files[0], 'r') as orig:
            for i, line in enumerate(orig):
                if not i in range(first_file_instantiation_line-1, first_file_instantiation_line+2):
                    f.write(replacer.sub("", line))

                if i == first_file_instantiation_line:
                    f.write("\n\n".join(all_instantiations))
                    f.write("\n")


    print(f"Merged {len(ads_files)} files into {output_file}")
    for f in ads_files:
        os.remove(f)

if __name__ == "__main__":
    merge_files()
