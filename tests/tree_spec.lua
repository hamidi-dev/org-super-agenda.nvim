local Item = require('org-super-agenda.core.item')
local layout_tree = require('org-super-agenda.core.layout.tree')

describe('layout.tree', function()
  local cfg = {
    group_format = '* %s',
    show_filename = false,
    show_tags = false,
    heading_max_length = 80,
    classic = { heading_order = { 'todo', 'headline' }, short_date_labels = false, inline_dates = false },
    tree = { show_ghost_parents = true },
  }

  local FILE = '/org/test.org'

  local function anc(headline, line, todo)
    return {
      key = string.format('%s:%s', FILE, line),
      headline = headline,
      level = 1,
      todo_state = todo,
      file = FILE,
      _src_line = line,
    }
  end

  local function make(headline, line, parents, extra)
    local o = {
      headline = headline,
      todo_state = 'TODO',
      file = FILE,
      _src_line = line,
      parents = parents or {},
    }
    for k, v in pairs(extra or {}) do
      o[k] = v
    end
    return Item.new(o)
  end

  local function build(items, opts)
    local groups = { { name = 'Work', collapsed = opts and opts.collapsed or false, items = items } }
    return layout_tree.build(groups, 80, (opts and opts.cfg) or cfg, (opts and opts.marked) or {})
  end

  it('nests a subtask under its parent', function()
    local parent = make('Project', 1)
    local child = make('Subtask', 2, { anc('Project', 1, 'TODO') })
    local rows, _, line_map = build({ parent, child })
    assert.equals('* Work (2 items)', rows[2])
    assert.equals('  TODO Project', rows[3])
    assert.equals('  └─ TODO Subtask', rows[4])
    assert.equals(parent, line_map[3])
    assert.equals(child, line_map[4])
  end)

  it('uses mid/last connectors and continuation bars', function()
    local parent = make('Project', 1)
    local a = make('Task A', 2, { anc('Project', 1, 'TODO') })
    local sub = make('Sub A1', 3, { anc('Task A', 2, 'TODO'), anc('Project', 1, 'TODO') })
    local b = make('Task B', 4, { anc('Project', 1, 'TODO') })
    local rows = build({ parent, a, sub, b })
    assert.equals('  TODO Project', rows[3])
    assert.equals('  ├─ TODO Task A', rows[4])
    assert.equals('  │  └─ TODO Sub A1', rows[5])
    assert.equals('  └─ TODO Task B', rows[6])
  end)

  it('inserts a dimmed ghost row for a parent not in the group', function()
    local child = make('Subtask', 5, { anc('Hidden Project', 1, nil) })
    local rows, _, line_map = build({ child })
    assert.equals('  Hidden Project', rows[3])
    assert.equals('  └─ TODO Subtask', rows[4])
    assert.is_true(line_map[3]._ghost)
    assert.equals(FILE, line_map[3].file)
    assert.equals(1, line_map[3]._src_line)
  end)

  it('shows the ghost todo state when the ancestor has one', function()
    local child = make('Subtask', 5, { anc('Waiting Project', 1, 'WAITING') })
    local rows = build({ child })
    assert.equals('  WAITING Waiting Project', rows[3])
  end)

  it('deduplicates a shared ghost parent across siblings', function()
    local a = make('Task A', 5, { anc('Hidden Project', 1, nil) })
    local b = make('Task B', 6, { anc('Hidden Project', 1, nil) })
    local rows = build({ a, b })
    assert.equals('  Hidden Project', rows[3])
    assert.equals('  ├─ TODO Task A', rows[4])
    assert.equals('  └─ TODO Task B', rows[5])
    assert.is_nil(rows[6])
  end)

  it('bridges a missing middle ancestor with a ghost under a real grandparent', function()
    local grand = make('Grandparent', 1)
    local child = make('Leaf', 5, { anc('Missing Parent', 3, nil), anc('Grandparent', 1, 'TODO') })
    local rows = build({ grand, child })
    assert.equals('  TODO Grandparent', rows[3])
    assert.equals('  └─ Missing Parent', rows[4])
    assert.equals('     └─ TODO Leaf', rows[5])
  end)

  it('renders items as roots when ghost parents are disabled', function()
    local no_ghost_cfg = vim.tbl_deep_extend('force', vim.deepcopy(cfg), { tree = { show_ghost_parents = false } })
    local child = make('Subtask', 5, { anc('Hidden Project', 1, nil) })
    local rows = build({ child }, { cfg = no_ghost_cfg })
    assert.equals('  TODO Subtask', rows[3])
    assert.is_nil(rows[4])
  end)

  it('still nests under a real ancestor when ghosts are disabled', function()
    local no_ghost_cfg = vim.tbl_deep_extend('force', vim.deepcopy(cfg), { tree = { show_ghost_parents = false } })
    local grand = make('Grandparent', 1)
    local child = make('Leaf', 5, { anc('Missing Parent', 3, nil), anc('Grandparent', 1, 'TODO') })
    local rows = build({ grand, child }, { cfg = no_ghost_cfg })
    assert.equals('  TODO Grandparent', rows[3])
    assert.equals('  └─ TODO Leaf', rows[4])
  end)

  it('suppresses the has_more ellipsis when subtasks are visible', function()
    local parent = make('Project', 1, nil, { has_more = true })
    local child = make('Subtask', 2, { anc('Project', 1, 'TODO') })
    local lonely = make('Lonely', 10, nil, { has_more = true })
    local rows = build({ parent, child, lonely })
    assert.equals('  TODO Project', rows[3])
    assert.equals('  └─ TODO Subtask', rows[4])
    assert.equals('  TODO Lonely …', rows[5])
  end)

  it('hides items and ghosts when the group is collapsed', function()
    local child = make('Subtask', 5, { anc('Hidden Project', 1, nil) })
    local rows, _, line_map = build({ child }, { collapsed = true })
    assert.equals('* Work (1 item)', rows[2])
    assert.is_nil(rows[3])
    assert.equals('group_header', line_map[2]._kind)
  end)

  it('keeps items from different files apart', function()
    local a = make('Task A', 1)
    local b = Item.new({ headline = 'Task B', todo_state = 'TODO', file = '/org/other.org', _src_line = 1, parents = {} })
    local rows = build({ a, b })
    assert.equals('  TODO Task A', rows[3])
    assert.equals('  TODO Task B', rows[4])
  end)
end)
