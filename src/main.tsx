import React from 'react';
import {createRoot} from 'react-dom/client';
import {InstallProvider} from './InstallApp';
import {App} from './App';
import './style.css';
createRoot(document.getElementById('root')!).render(<React.StrictMode><InstallProvider><App/></InstallProvider></React.StrictMode>);
