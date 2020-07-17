module {
  name:        "neuron-autoindex",
  version:     "0.1.0",
  description: "generate hierarchical indices for neuron notes",
  authors:     ["Maddison Hellstrom <maddy@na.ai>"],
  license:     "GPL-3",
};

def invert_tags:
  .
  | [
    .
    | .[]
    | .value
    | select((.indexTags // []) != [])
    | . as $z
    | .indexTags
    | .[]
    | {
        tag: .,
        zettels: [$z]
      }
    ]
  | reduce .[] as $t ({}; .[$t.tag].zettels += $t.zettels)
;

def with_tagPaths:
  .
  | .tagPath = (.tagPath // (.key | split("/")))
;

def treeify:
  .
  | (.tagPath | length) as $len
  | (.tagPath[0]) as $cur
  | if $len == 0 then
      empty
    elif $len == 1 then
      { zettels: (
          .value
        | .zettels
        )
      }
    else
      { children:
        [ ( .tagPath = .tagPath[1:]
          | treeify
          )
        ]
      }
    end
  | [{
      key: $cur,
      value: .
    }]
  | from_entries
;

def filter_key(key):
  .
  | map(
      .
      | to_entries
      | map(select(.key? == key))
    )
  | flatten(1)
;

def gather_keys:
  .
  | reduce .[] as $e ([];
      .
      | . as $acc
      | $e
      | to_entries
      | map(.key)
      | . + $acc
    )
  | unique
;

def merge_recursive:
  .
  | . as $in
  | ($in | gather_keys) as $keys
  | reduce ($keys | .[]) as $key ([];
      .
      | . + [{
        key: $key,
        value: (
          $in
          | filter_key($key)
          | reduce .[] as $e ({ zettels: [], children: [] };
              .
              | . as $acc
              | $e.value
              | {
                  # sort zettels: date DESC, title ASC
                  # assumes zettelDay is in YYYY-MM-DD format
                  zettels: ($acc.zettels + .zettels | group_by(.zettelDay) | sort_by(.[0].zettelDay) | reverse | map(sort_by(.zettelTitle)) | flatten(1)),
                  children: ($acc.children + .children)
                }
            )
          | .children = (.children | merge_recursive)
        )
      }]
    )
  | from_entries
;

def as_tagTree:
  .
  | invert_tags
  | to_entries
  | map(with_tagPaths)
  | map(treeify)
  | merge_recursive
;

def as_indices(base):
  .
  | to_entries
  | map(
      .
      | (base + [.key]) as $path
      | .value.children as $children
      | [{
          name: ($path | join("-")),
          title: (if ($path | length) > 1 then $path[1:] else [$path[0]] end | join("/")),
          zettels: (.value.zettels | map(.zettelID)),
          children: ((.value.children | keys) | map($path + [.] | join("-"))),
        }]
      | . + ($children | as_indices($path))
    )
  | flatten(1)
;
def as_indices: as_indices([]);

def as_file:
  .
  | {
      name: (.name + ".md"),
      content: ([
        "---",
        "date: \"\(now | strftime("%Y-%m-%d"))\"",
        "tags:",
        "  - index",
        "---",
        "",
        "# \(.title)"
      ] + (
          if (.children | length) > 0 then
            [
              "",
              "## index",
              (.children | .[] | "- <\(.)>")
            ]
          else
            []
          end
      ) + (
          if (.zettels | length) > 0 then
            [
              "",
              "## zettels",
              (.zettels | .[] | "- <\(.)?cf>")
            ]
          else
            []
          end
      ) + [
        "",
        ""
      ]),
    }
;

def as_command(basedir):
  .
  | (basedir + "/" + .name | @sh) as $file
  | "echo '\($file)' >&2\n"
  + "cat > \($file) <<\"EOF\"\n"
  + (.content | join("\n"))
  + "EOF\n"
;

def main(basedir; index):
  .
  | .result
  | .vertices
  | to_entries
  | map(.value.indexTags = (.value.zettelTags | map(select(startswith(index + "/")))))
  | map(select((.value.indexTags | length) > 0))
  | as_tagTree
  | as_indices
  | map(as_file)
  | map(as_command(basedir))
  | "rm \(basedir + "/" + index + "-" | @sh)* &>/dev/null || true", .[]
;

def main: main("\($ENV.HOME)/zettelkasten"; "index");
