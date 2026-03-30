# Test Large Markdown File

This is a test file to verify that the optimized markdown preview is working correctly in Yazi.

## Section 1: Introduction

This file contains multiple sections and plenty of content to test the 200-line limit functionality.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

## Section 2: Code Examples

Here are some code examples to test syntax highlighting:

```bash
#!/bin/bash
echo "Hello, World!"
for i in {1..10}; do
    echo "Line $i"
done
```

```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

for i in range(10):
    print(f"F({i}) = {fibonacci(i)}")
```

## Section 3: Lists and Tables

### Unordered List
- Item 1
- Item 2
  - Subitem 2.1
  - Subitem 2.2
- Item 3

### Ordered List
1. First item
2. Second item
3. Third item

### Table
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Data 1   | Data 2   | Data 3   |
| Data 4   | Data 5   | Data 6   |
| Data 7   | Data 8   | Data 9   |

## Section 4: More Content

Adding more lines to test the 200-line limit...

Line 51
Line 52
Line 53
Line 54
Line 55
Line 56
Line 57
Line 58
Line 59
Line 60
Line 61
Line 62
Line 63
Line 64
Line 65
Line 66
Line 67
Line 68
Line 69
Line 70
Line 71
Line 72
Line 73
Line 74
Line 75
Line 76
Line 77
Line 78
Line 79
Line 80
Line 81
Line 82
Line 83
Line 84
Line 85
Line 86
Line 87
Line 88
Line 89
Line 90
Line 91
Line 92
Line 93
Line 94
Line 95
Line 96
Line 97
Line 98
Line 99
Line 100
Line 101
Line 102
Line 103
Line 104
Line 105
Line 106
Line 107
Line 108
Line 109
Line 110
Line 111
Line 112
Line 113
Line 114
Line 115
Line 116
Line 117
Line 118
Line 119
Line 120
Line 121
Line 122
Line 123
Line 124
Line 125
Line 126
Line 127
Line 128
Line 129
Line 130
Line 131
Line 132
Line 133
Line 134
Line 135
Line 136
Line 137
Line 138
Line 139
Line 140
Line 141
Line 142
Line 143
Line 144
Line 145
Line 146
Line 147
Line 148
Line 149
Line 150
Line 151
Line 152
Line 153
Line 154
Line 155
Line 156
Line 157
Line 158
Line 159
Line 160
Line 161
Line 162
Line 163
Line 164
Line 165
Line 166
Line 167
Line 168
Line 169
Line 170
Line 171
Line 172
Line 173
Line 174
Line 175
Line 176
Line 177
Line 178
Line 179
Line 180
Line 181
Line 182
Line 183
Line 184
Line 185
Line 186
Line 187
Line 188
Line 189
Line 190
Line 191
Line 192
Line 193
Line 194
Line 195
Line 196
Line 197
Line 198
Line 199
Line 200
Line 201 - This line should NOT appear in the preview!
Line 202 - This line should also be hidden!
Line 203 - You won't see this either!
Line 204 - Still hidden...
Line 205 - The script should truncate at line 200!

## Section 5: Content After Line 200

This entire section should be hidden when using the optimized preview script.

### More Tables
| Hidden | Content | Here |
|--------|---------|------|
| X      | Y       | Z    |

### More Code
```javascript
console.log("This code block should not be visible!");
```

The end of the file.
