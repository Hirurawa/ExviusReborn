import json
from pathlib import Path

import parse
import town_parser


VALID_WARPS = {"warp", "warp_alt", "warp_zone", "warp_exit"}


def test_all_map_warps():
    assert parse.parse_all()
    compact_warps = []
    for map_bin in Path(town_parser.TOWN_DATA_ROOT).glob("*/map.bin"):
        blueprint = json.loads(map_bin.with_name("map_blueprint.json").read_text())
        dimensions = {
            layer["layer_id"]: (layer["grid_width"], layer["grid_height"])
            for layer in blueprint["layers"]
        }
        for layer in blueprint["layers"]:
            for entity in layer["objects"]["dynamic_entities"]:
                if entity.get("note") == "recovered compact warp header":
                    compact_warps.append(entity)
                if entity.get("kind") not in VALID_WARPS:
                    continue
                target = entity["target_lid"]
                if target not in dimensions:  # external map transition
                    continue
                width, height = dimensions[target]
                assert 0 <= entity["target_x"] < width
                assert 0 <= entity["target_y"] < height

    assert compact_warps
    assert any(entity["target_lid"] == 59 for entity in compact_warps)


if __name__ == "__main__":
    test_all_map_warps()
    print("All map warps: ok")
