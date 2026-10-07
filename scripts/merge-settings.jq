# Three-way merge of declared settings into an app-written JSON file.
# Input: the live file. $declared[0]: repo settings. $base[0]: the declared
# settings from the previous apply (absent on first merge).
# - declared keys take the declared value; runtime-only keys are kept
# - keys dropped from the declaration since the base are removed
# - arrays keep runtime additions and drop entries removed from the declaration
def merge3($base; $declared):
  if ($declared | type) == "object" and type == "object" then
    . as $live
    | ($base | if type == "object" then . else {} end) as $old
    | reduce (($live | keys_unsorted) + (($declared | keys_unsorted) - ($live | keys_unsorted)))[] as $key ({};
        if ($declared | has($key)) then
          .[$key] = (if ($live | has($key)) then ($live[$key] | merge3($old[$key]; $declared[$key])) else $declared[$key] end)
        elif ($old | has($key)) then .
        else .[$key] = $live[$key] end)
  elif ($declared | type) == "array" and type == "array" then
    . as $live
    | ($base | if type == "array" then . else [] end) as $old
    | $declared + [$live[] | . as $item | select(($declared | index([$item])) == null and ($old | index([$item])) == null)]
  else $declared end;

merge3($base[0]; $declared[0])
