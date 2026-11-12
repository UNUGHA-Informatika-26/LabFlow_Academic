import path from 'node:path';
import fs from 'node:fs';

export const Selectors = {
  // Authentication
  emailInput: () => $('android=new UiSelector().className("android.widget.EditText").instance(0)'),
  passwordInput: () => $('android=new UiSelector().className("android.widget.EditText").instance(1)'),
  loginButton: () => $('android=new UiSelector().description("Masuk")'),
  forgotPasswordButton: () => $('android=new UiSelector().descriptionContains("Lupa password")'),
  
  // Generic Helpers
  byDescription: (desc) => $(`android=new UiSelector().description("${desc}")`),
  byDescriptionContains: (text) => $(`android=new UiSelector().descriptionContains("${text}")`),
  byText: (text) => $(`android=new UiSelector().text("${text}")`),
  byTextContains: (text) => $(`android=new UiSelector().textContains("${text}")`),
  
  // Navigation & Role Check
  superadminDashboard: () => $('android=new UiSelector().descriptionContains("Superadmin")'),
  kelolaPenggunaMenu: () => $('android=new UiSelector().descriptionContains("Kelola Pengguna")'),
  kelolaLaboratoriumMenu: () => $('android=new UiSelector().descriptionContains("Kelola Laboratorium")'),
  
  // Dialog Actions
  confirmButton: (text = 'Konfirmasi') => $(`android=new UiSelector().description("${text}")`),
  cancelButton: () => $('android=new UiSelector().description("Batal")'),
};
