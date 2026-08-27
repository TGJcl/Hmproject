export interface DeepSeekMessage {
  role: string;
  content: string;
}

export interface DeepSeekChoice {
  message: DeepSeekMessage;
}

export interface DeepSeekResponse {
  choices: Array<DeepSeekChoice>;
}
