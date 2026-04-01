const STORAGE_KEY = 'ruggero-os-state';

const state = loadState();
const el = {
  contactsList: document.getElementById('contactsList'),
  tasksList: document.getElementById('tasksList'),
  opportunitiesList: document.getElementById('opportunitiesList'),
  contactsCount: document.getElementById('contactsCount'),
  tasksCount: document.getElementById('tasksCount'),
  pipelineValue: document.getElementById('pipelineValue'),
  docsCount: document.getElementById('docsCount'),
  generatedOutput: document.getElementById('generatedOutput')
};

document.getElementById('contactForm').addEventListener('submit', onAddContact);
document.getElementById('taskForm').addEventListener('submit', onAddTask);
document.getElementById('opportunityForm').addEventListener('submit', onAddOpportunity);
document.getElementById('docForm').addEventListener('submit', onGenerateDoc);
document.getElementById('copyOutputBtn').addEventListener('click', copyOutput);
document.getElementById('seedDemoBtn').addEventListener('click', seedDemoData);
document.getElementById('resetBtn').addEventListener('click', resetAll);

render();

function loadState() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) || defaultState();
  } catch {
    return defaultState();
  }
}

function defaultState() {
  return {
    contacts: [],
    tasks: [],
    opportunities: [],
    generatedDocs: 0
  };
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function onAddContact(event) {
  event.preventDefault();
  const form = new FormData(event.target);
  state.contacts.unshift({
    id: crypto.randomUUID(),
    name: form.get('name'),
    email: form.get('email'),
    phone: form.get('phone'),
    tag: form.get('tag')
  });
  event.target.reset();
  commit();
}

function onAddTask(event) {
  event.preventDefault();
  const form = new FormData(event.target);
  state.tasks.unshift({
    id: crypto.randomUUID(),
    title: form.get('title'),
    priority: form.get('priority'),
    deadline: form.get('deadline'),
    done: false
  });
  event.target.reset();
  commit();
}

function onAddOpportunity(event) {
  event.preventDefault();
  const form = new FormData(event.target);
  state.opportunities.unshift({
    id: crypto.randomUUID(),
    name: form.get('name'),
    value: Number(form.get('value') || 0),
    status: form.get('status')
  });
  event.target.reset();
  commit();
}

function onGenerateDoc(event) {
  event.preventDefault();
  const form = new FormData(event.target);
  const template = form.get('template');
  const subject = form.get('subject');
  const details = form.get('details');
  el.generatedOutput.value = buildTemplate(template, subject, details);
  state.generatedDocs += 1;
  commit();
}

function buildTemplate(template, subject, details) {
  const today = new Date().toLocaleDateString();
  const cleanDetails = details?.trim() || 'No extra details provided.';

  const templates = {
    proposal: `QUICK PROPOSAL\n\nDate: ${today}\nSubject: ${subject}\n\nContext\n${cleanDetails}\n\nSuggested scope\n- initial setup\n- workflow configuration\n- delivery of first usable version\n\nCommercial frame\n- one-time setup\n- optional monthly support\n\nNext step\nConfirm interest and schedule a short operational call.`,
    followup: `FOLLOW-UP EMAIL\n\nSubject: Follow-up regarding ${subject}\n\nHello,\n\nI am following up regarding ${subject}. Based on the current context:\n${cleanDetails}\n\nI suggest a short next step to unblock progress and move toward execution.\n\nBest regards`,
    meeting: `MEETING SUMMARY\n\nDate: ${today}\nTopic: ${subject}\n\nKey points\n${cleanDetails}\n\nAgreed next actions\n- confirm priorities\n- assign owner\n- set next review date`,
    post: `SOCIAL POST\n\nToday we are working on ${subject}.\n\nWhy it matters:\n${cleanDetails}\n\nThe goal is simple: turn scattered activity into clear execution.\n\n#operations #productivity #smallbusiness #ai`
  };

  return templates[template] || '';
}

function copyOutput() {
  if (!el.generatedOutput.value) return;
  navigator.clipboard.writeText(el.generatedOutput.value);
}

function seedDemoData() {
  state.contacts = [
    { id: crypto.randomUUID(), name: 'Silvana Pollice', email: 'silvana@example.com', phone: '3400000000', tag: 'association' },
    { id: crypto.randomUUID(), name: 'Teatro Demo', email: 'info@teatrodemo.it', phone: '080000000', tag: 'theatre' }
  ];
  state.tasks = [
    { id: crypto.randomUUID(), title: 'Prepare pilot offer', priority: 'High', deadline: '2026-04-07', done: false },
    { id: crypto.randomUUID(), title: 'Send follow-up to prospect', priority: 'Medium', deadline: '2026-04-08', done: false }
  ];
  state.opportunities = [
    { id: crypto.randomUUID(), name: 'Association setup package', value: 299, status: 'Proposal' },
    { id: crypto.randomUUID(), name: 'Theatre content workflow', value: 499, status: 'Lead' }
  ];
  state.generatedDocs = 3;
  el.generatedOutput.value = 'Demo content loaded.';
  commit();
}

function resetAll() {
  localStorage.removeItem(STORAGE_KEY);
  Object.assign(state, defaultState());
  el.generatedOutput.value = '';
  render();
}

function commit() {
  saveState();
  render();
}

function render() {
  renderContacts();
  renderTasks();
  renderOpportunities();
  updateStats();
}

function renderContacts() {
  el.contactsList.innerHTML = state.contacts.map(contact => `
    <div class="item">
      <div class="item-head">
        <strong>${escapeHtml(contact.name)}</strong>
        <button class="delete-btn" onclick="removeItem('contacts','${contact.id}')">Delete</button>
      </div>
      <div class="small">${escapeHtml(contact.email)} · ${escapeHtml(contact.phone || '')}</div>
      <div class="small">${escapeHtml(contact.tag || 'untagged')}</div>
    </div>
  `).join('') || '<p class="small">No contacts yet.</p>';
}

function renderTasks() {
  el.tasksList.innerHTML = state.tasks.map(task => `
    <div class="item">
      <div class="item-head">
        <strong class="${task.done ? 'done' : ''}">${escapeHtml(task.title)}</strong>
        <div>
          <button class="delete-btn" onclick="toggleTask('${task.id}')">${task.done ? 'Undo' : 'Done'}</button>
          <button class="delete-btn" onclick="removeItem('tasks','${task.id}')">Delete</button>
        </div>
      </div>
      <div class="small">${escapeHtml(task.priority)} priority ${task.deadline ? '· due ' + escapeHtml(task.deadline) : ''}</div>
    </div>
  `).join('') || '<p class="small">No tasks yet.</p>';
}

function renderOpportunities() {
  el.opportunitiesList.innerHTML = state.opportunities.map(item => `
    <div class="item">
      <div class="item-head">
        <strong>${escapeHtml(item.name)}</strong>
        <button class="delete-btn" onclick="removeItem('opportunities','${item.id}')">Delete</button>
      </div>
      <div class="small">${escapeHtml(item.status)} · €${Number(item.value).toLocaleString()}</div>
    </div>
  `).join('') || '<p class="small">No opportunities yet.</p>';
}

function updateStats() {
  el.contactsCount.textContent = state.contacts.length;
  el.tasksCount.textContent = state.tasks.filter(t => !t.done).length;
  el.pipelineValue.textContent = '€' + state.opportunities.reduce((sum, item) => sum + Number(item.value || 0), 0).toLocaleString();
  el.docsCount.textContent = state.generatedDocs;
}

function toggleTask(id) {
  const task = state.tasks.find(item => item.id === id);
  if (!task) return;
  task.done = !task.done;
  commit();
}

function removeItem(collection, id) {
  state[collection] = state[collection].filter(item => item.id !== id);
  commit();
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

window.toggleTask = toggleTask;
window.removeItem = removeItem;
