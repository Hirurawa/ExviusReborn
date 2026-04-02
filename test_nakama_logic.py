import re

with open('nakama/modules/main.lua', 'r') as f:
    content = f.read()

# Let's ensure the get_player_stats is correct
match = re.search(r'local function get_player_stats\(context, payload\)(.*?)end', content, re.DOTALL)
if match:
    print("Found get_player_stats")
    func_content = match.group(0)
    print("contains current_nrg:", 'current_nrg' in func_content)
    print("contains nrg_regen_rate_seconds:", 'nrg_regen_rate_seconds' in func_content)
else:
    print("Failed to find get_player_stats")
