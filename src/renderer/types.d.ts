import { DropperApi } from '../shared/api';

declare global {
  interface Window {
    dropperApi: DropperApi;
  }
}

export {};
