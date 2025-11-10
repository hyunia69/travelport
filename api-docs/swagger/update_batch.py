import re

with open('index-batch.html', 'r', encoding='utf-8') as f:
    content = f.read()

api_section = '''    <!-- API Endpoint Information -->
    <div class="info-section">
        <h3>정보 추가됨</h3>
    </div>

'''

pattern = r'(    <!-- Feature Highlight -->)'
content = re.sub(pattern, api_section + r'\1', content, count=1)

with open('index-batch.html', 'w', encoding='utf-8') as f:
    f.write(content)

print("Complete")
