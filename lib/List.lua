-- list.lua ── односвязный список
-- API:
--   local List = require "list"
--   local l = List.new()
--   l:push_front(1)  l:push_back(2)
--   for v in l:iter() do print(v) end
local List = {}
List.__index = List

-- ─── конструктор ────────────────────────────────────────────────────────────
function List.new()
    return setmetatable({
        head = nil, -- первый узел
        tail = nil, -- последний узел (ускоряет push_back)
        size = 0 -- количество элементов
    }, List)
end

-- ─── внутренний «узел» ──────────────────────────────────────────────────────
local function new_node(value, next)
    return {
        value = value,
        next = next
    }
end

-- ─── основные операции ─────────────────────────────────────────────────────
function List:is_empty()
    return self.head == nil
end
function List:length()
    return self.size
end

function List:push_front(value) -- O(1)
    self.head = new_node(value, self.head)
    if not self.tail then
        self.tail = self.head
    end
    self.size = self.size + 1
end

function List:push_back(value) -- O(1) благодаря tail
    local node = new_node(value, nil)
    if self.tail then
        self.tail.next = node
    else
        self.head = node
    end
    self.tail = node
    self.size = self.size + 1
end

function List:pop_front() -- O(1)
    if not self.head then
        return nil
    end
    local value = self.head.value
    self.head = self.head.next
    if not self.head then
        self.tail = nil
    end
    self.size = self.size - 1
    return value
end

-- удаляет **первое** вхождение value, возвращает true/false
function List:remove(value, eq)
    eq = eq or function(a, b)
        return a == b
    end
    local prev, node = nil, self.head
    while node do
        if eq(node.value, value) then
            if prev then
                prev.next = node.next
            else
                self.head = node.next
            end
            if node == self.tail then
                self.tail = prev
            end
            self.size = self.size - 1
            return true
        end
        prev, node = node, node.next
    end
    return false
end

-- итератор: for v in list:iter() do … end
function List:iter()
    local node = self.head
    return function()
        if node then
            local v = node.value
            node = node.next
            return v
        end
    end
end

-- поиск узла; возвращает сам узел или nil
function List:find(value, eq)
    eq = eq or function(a, b)
        return a == b
    end
    local node = self.head
    while node do
        if eq(node.value, value) then
            return node
        end
        node = node.next
    end
    return nil
end

_G.List = List

return List
