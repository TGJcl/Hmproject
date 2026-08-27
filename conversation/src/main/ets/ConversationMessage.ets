export interface ConversationMessage {
  id: number;
  sessionId: string;
  role: string;
  text: string;
  createdAt: number;
}