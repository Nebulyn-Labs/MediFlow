const USER_INPUT_DELIMITER_OPEN = '---BEGIN USER INPUT---';
const USER_INPUT_DELIMITER_CLOSE = '---END USER INPUT---';

const DATA_DELIMITER_OPEN = '---BEGIN DATA---';
const DATA_DELIMITER_CLOSE = '---END DATA---';

function sanitizeUserInput(str) {
  if (typeof str !== 'string') return '';
  return str
    .replace(/[\0\x08\x0B\x1A]/g, '')
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\r\n/g, ' ')
    .replace(/\r/g, ' ')
    .replace(/\n/g, ' ')
    .replace(/\t/g, ' ');
}

function wrapUserContent(content) {
  const safe = typeof content === 'string' ? content : JSON.stringify(content);
  return `${USER_INPUT_DELIMITER_OPEN}\n${safe}\n${USER_INPUT_DELIMITER_CLOSE}`;
}

function wrapDataContent(content) {
  const safe = typeof content === 'string' ? content : JSON.stringify(content);
  return `${DATA_DELIMITER_OPEN}\n${safe}\n${DATA_DELIMITER_CLOSE}`;
}

function buildSystemPrompt(systemInstruction) {
  return systemInstruction;
}

function buildPrompt(systemInstruction, userContent) {
  const userPart = wrapUserContent(userContent);
  return `${systemInstruction}\n\n${userPart}`;
}

function buildPromptWithData(systemInstruction, data, userContent) {
  const dataPart = wrapDataContent(data);
  const userPart = userContent ? wrapUserContent(userContent) : '';
  return `${systemInstruction}\n\n${dataPart}${userPart ? `\n\n${userPart}` : ''}`;
}

module.exports = {
  sanitizeUserInput,
  wrapUserContent,
  wrapDataContent,
  buildSystemPrompt,
  buildPrompt,
  buildPromptWithData,
  USER_INPUT_DELIMITER_OPEN,
  USER_INPUT_DELIMITER_CLOSE,
  DATA_DELIMITER_OPEN,
  DATA_DELIMITER_CLOSE,
};
