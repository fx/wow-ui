-- Line-coverage gate over luacov's report (see `.luacov`).
-- Run with: mise run coverage   (or lua tests/coverage.lua [threshold] [report])
-- Exits non-zero when total line coverage is below the threshold (80 %).

local M = { THRESHOLD = 80 }

-- Hits and misses per file and in total, from the report's Summary table.
function M.parse(text)
  local summary = text:match("\nSummary\n=+\n(.*)$")
  if not summary then return nil, "no Summary section in the report" end
  local files, hits, missed = {}, 0, 0
  for line in summary:gmatch("[^\n]+") do
    local name, h, m = line:match("^(%S+)%s+(%d+)%s+(%d+)%s+[%d.]+%%$")
    if name and name ~= "Total" then
      h, m = tonumber(h), tonumber(m)
      files[#files + 1] = { name = name, hits = h, missed = m, percent = h + m > 0 and 100 * h / (h + m) or 100 }
      hits, missed = hits + h, missed + m
    end
  end
  if #files == 0 then return nil, "no files in the report" end
  return { files = files, hits = hits, missed = missed, percent = 100 * hits / (hits + missed) }
end

-- passed, lines to print.
function M.check(text, threshold)
  threshold = threshold or M.THRESHOLD
  local cov, err = M.parse(text)
  if not cov then return false, { "coverage: " .. err } end
  local files = {}
  for i, f in ipairs(cov.files) do files[i] = f end
  table.sort(files, function(a, b) return a.percent < b.percent end)
  local out = {}
  for _, f in ipairs(files) do
    out[#out + 1] = string.format("%7.2f%%  %5d missed  %s", f.percent, f.missed, f.name)
  end
  local passed = cov.percent >= threshold
  out[#out + 1] = string.format("coverage: %.2f%% of %d lines (threshold %d%%): %s",
    cov.percent, cov.hits + cov.missed, threshold, passed and "ok" or "FAIL")
  return passed, out
end

-- Loaded by the tests (dofile) rather than run: hand back the functions.
if not (arg and arg[0] and arg[0]:match("coverage%.lua$")) then return M end

local threshold = tonumber(arg[1]) or M.THRESHOLD
local path = arg[2] or "luacov.report.out"
local fh = io.open(path)
if not fh then
  print("coverage: no report at " .. path .. " (run the tests under luacov first)")
  os.exit(1)
end
local text = fh:read("*a")
fh:close()
local passed, lines = M.check(text, threshold)
print(table.concat(lines, "\n"))
os.exit(passed and 0 or 1)
