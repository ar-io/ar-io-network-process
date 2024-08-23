QueueNode = {}
QueueNode.__index = QueueNode

function QueueNode:new(value)
	local node = { value = value, next = nil, prev = nil }
	setmetatable(node, self)
	return node
end

PriorityDeque = {}
PriorityDeque.__index = PriorityDeque

function PriorityDeque:new(comparator)
	local obj = { head = nil, tail = nil, comparator = comparator, size = 0 }
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

return PriorityDeque
