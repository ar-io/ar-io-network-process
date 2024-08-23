### PriorityDeque Implementation

Here's how you can implement a `PriorityDeque` in Lua:

```lua
QueueNode = {}
QueueNode.__index = QueueNode

function QueueNode:new(value)
    local node = {value = value, next = nil, prev = nil}
    setmetatable(node, self)
    return node
end

PriorityDeque = {}
PriorityDeque.__index = PriorityDeque

function PriorityDeque:new(comparator)
    local obj = {head = nil, tail = nil, comparator = comparator, size = 0}
    setmetatable(obj, self)
    return obj
end

-- Enqueue at the head with prioritization
function PriorityDeque:enqueueHead(value)
    local newNode = QueueNode:new(value)
    if not self.head then
        self.head = newNode
        self.tail = newNode
    else
        local current = self.head
        while current and self.comparator(value, current.value) > 0 do
            current = current.next
        end
        if not current then
            self.tail.next = newNode
            newNode.prev = self.tail
            self.tail = newNode
        else
            newNode.next = current
            newNode.prev = current.prev
            if current.prev then
                current.prev.next = newNode
            else
                self.head = newNode
            end
            current.prev = newNode
        end
    end
    self.size = self.size + 1
end

-- Enqueue at the tail with prioritization
function PriorityDeque:enqueueTail(value)
    local newNode = QueueNode:new(value)
    if not self.tail then
        self.head = newNode
        self.tail = newNode
    else
        local current = self.tail
        while current and self.comparator(current.value, value) > 0 do
            current = current.prev
        end
        if not current then
            self.head.prev = newNode
            newNode.next = self.head
            self.head = newNode
        else
            newNode.prev = current
            newNode.next = current.next
            if current.next then
                current.next.prev = newNode
            else
                self.tail = newNode
            end
            current.next = newNode
        end
    end
    self.size = self.size + 1
end

function PriorityDeque:dequeueHead()
    if not self.head then
        error("Deque is empty")
    end
    local value = self.head.value
    self.head = self.head.next
    if self.head then
        self.head.prev = nil
    else
        self.tail = nil
    end
    self.size = self.size - 1
    return value
end

function PriorityDeque:dequeueTail()
    if not self.tail then
        error("Deque is empty")
    end
    local value = self.tail.value
    self.tail = self.tail.prev
    if self.tail then
        self.tail.next = nil
    else
        self.head = nil
    end
    self.size = self.size - 1
    return value
end

function PriorityDeque:peekHead()
    if not self.head then
        error("Deque is empty")
    end
    return self.head.value
end

function PriorityDeque:peekTail()
    if not self.tail then
        error("Deque is empty")
    end
    return self.tail.value
end

function PriorityDeque:getSize()
    return self.size
end
```

### Explanation:

1. **QueueNode:** Each node in the deque has a `value`, a `next` pointer to the next node, and a `prev` pointer to the previous node. This doubly linked list structure allows efficient traversal in both directions.

2. **PriorityDeque Initialization:** The `PriorityDeque` is initialized with a comparator function. This function determines the order of elements in the deque. It should return:

   - A positive number if the first argument has higher priority than the second.
   - A negative number if the second argument has higher priority.
   - Zero if they have equal priority.

3. **Enqueue Methods:**

   - `enqueueHead`: Adds an element at the appropriate position starting from the head based on the comparator.
   - `enqueueTail`: Adds an element at the appropriate position starting from the tail.

4. **Dequeue Methods:**

   - `dequeueHead`: Removes and returns the element at the head.
   - `dequeueTail`: Removes and returns the element at the tail.

5. **Peek Methods:**

   - `peekHead`: Returns the value at the head without removing it.
   - `peekTail`: Returns the value at the tail without removing it.

6. **getSize Method:** Returns the current size of the deque.

### Example Usage:

```lua
-- Custom comparator function
local function comparator(a, b)
    return a - b -- Prioritize lower numbers
end

-- Create a new PriorityDeque with the comparator
local deque = PriorityDeque:new(comparator)

-- Enqueue elements at the head
deque:enqueueHead(10)
deque:enqueueHead(5)
deque:enqueueHead(15)

-- Enqueue elements at the tail
deque:enqueueTail(8)
deque:enqueueTail(3)

-- Dequeue elements
print(deque:dequeueHead())  -- Output: 3 (highest priority)
print(deque:dequeueTail())  -- Output: 15 (lowest priority)
print(deque:peekHead())     -- Output: 5
print(deque:peekTail())     -- Output: 10

print(deque:getSize())      -- Output: 3
```

### Summary:

This `PriorityDeque` implementation allows enqueuing at both the head and the tail while maintaining the order based on the given comparator function. It provides flexibility in how elements are prioritized and supports both head-first and tail-first operations with efficient time complexity, typically `O(n)` for enqueuing when the correct position needs to be determined.
