function createRingBuffer(size)
    local buffer = {
        data = {},
        size = size or 5,
        index = 1,
        count = 0
    }

    function buffer:add(value)
        self.data[self.index] = value
        self.index = self.index % self.size + 1
        self.count = math.min(self.count + 1, self.size)
    end

    function buffer:getAll()
        local result = {}
        local start = (self.index - self.count - 1 + self.size) % self.size + 1
        for i = 1, self.count do
            local idx = (start + i - 1 - 1) % self.size + 1
            table.insert(result, self.data[idx])
        end
        return result
    end

    return buffer
end

_G.createRingBuffer = createRingBuffer

return createRingBuffer
