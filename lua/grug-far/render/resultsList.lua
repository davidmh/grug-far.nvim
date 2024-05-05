local utils = require('grug-far/utils')
local renderResultsHeader = require('grug-far/render/resultsHeader')
local fetchResults = require('grug-far/rg/fetchResults')

local function asyncFetchResultList(params)
  local on_start = params.on_start
  local on_fetch_chunk = vim.schedule_wrap(params.on_fetch_chunk)
  local on_finish = vim.schedule_wrap(params.on_finish)
  local on_error = vim.schedule_wrap(params.on_error)
  local inputs = params.inputs
  local context = params.context

  if context.state.abortFetch then
    context.state.abortFetch();
    context.state.abortFetch = nil
  end

  on_start()
  context.state.abortFetch = fetchResults({
    inputs = inputs,
    on_fetch_chunk = on_fetch_chunk,
    on_finish = function(isSuccess)
      context.state.abortFetch = nil
      on_finish(isSuccess)
    end,
    on_error = on_error
  })
end

local function bufAppendResultsChunk(buf, context, data)
  local lastline = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, lastline, lastline, false, data.lines)

  local hlGroups = context.options.highlights
  for i = 1, #data.highlights do
    local highlight = data.highlights[i]
    local hlGroup = hlGroups[highlight.hl]
    if hlGroup then
      for j = highlight.start_line, highlight.end_line do
        vim.api.nvim_buf_add_highlight(buf, context.namespace, hlGroup, lastline + j,
          j == highlight.start_line and highlight.start_col or 0,
          j == highlight.end_line and highlight.end_col or -1)
      end
    end
  end
end

local function bufAppendErrorChunk(buf, context, error)
  local lastErrorLine = context.state.lastErrorLine

  local err_lines = vim.split(error, '\n')
  vim.api.nvim_buf_set_lines(buf, lastErrorLine, lastErrorLine, false, err_lines)

  for i = lastErrorLine, lastErrorLine + #err_lines do
    vim.api.nvim_buf_add_highlight(buf, context.namespace, 'DiagnosticError', i, 0, -1)
  end

  context.state.lastErrorLine = lastErrorLine + #err_lines
end

local function renderResultsList(buf, context, inputs, headerRow)
  local function updateStatus(newStatus, stats)
    context.state.status = newStatus
    if newStatus.status == 'progress' then
      if newStatus.count == 0 or not context.state.stats then
        context.state.stats = { matches = 0, files = 0 }
      end
      if stats then
        context.state.stats = {
          matches = context.state.stats.matches + stats.matches,
          files = context.state.stats.files + stats.files
        }
      end
    elseif newStatus.status ~= 'success' then
      context.state.stats = nil
    end

    renderResultsHeader(buf, context, headerRow)
  end

  -- TODO (sbadragan): figure out how to "commit" the replacement
  context.state.asyncFetchResultList = context.state.asyncFetchResultList or
    utils.debounce(asyncFetchResultList, context.options.debounceMs)
  context.state.asyncFetchResultList({
    inputs = inputs,
    on_start = function()
      updateStatus(#inputs.search > 0
        and { status = 'progress', count = 0 } or { status = nil })
      -- remove all lines after heading and add one blank line
      vim.api.nvim_buf_set_lines(buf, headerRow, -1, false, { "" })
      context.state.lastErrorLine = headerRow + 1
      context.state.stats = nil
    end,
    on_fetch_chunk = function(data)
      local status = context.state.status
      updateStatus({
        status = 'progress',
        count = status.count and status.count + 1 or 2
      }, data.stats)
      bufAppendResultsChunk(buf, context, data)
    end,
    on_error = function(error)
      updateStatus({ status = 'error' })
      bufAppendErrorChunk(buf, context, error)
    end,
    on_finish = function(isSuccess)
      updateStatus({ status = isSuccess and 'success' or 'error' })
    end,
    context = context
  })
end

return renderResultsList