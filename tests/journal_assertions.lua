local assert = require('luassert')
return function(log, expected)
    local observed = {}
    for _, call in ipairs(log.calls) do
        local entry = call.vals[1]
        if type(entry) == "table" then
            local actual, matches = {}, true
            for field, value in pairs(expected) do
                if field == "sourceName" then actual[field] = entry.source and entry.source.name
                elseif field == "targetName" then actual[field] = entry.target and entry.target.name
                else actual[field] = entry[field] end
                if actual[field] ~= value then matches = false end
            end
            if matches then return end
            observed[#observed + 1] = actual
        end
    end
    assert.are.same({ expected }, observed)
end
