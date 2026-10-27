import { Routes, Route, Navigate } from 'react-router-dom';
import Login from './pages/Login';
import Register from './pages/Register';
import DashboardLayout from './components/DashboardLayout';
import Dashboard from './pages/Dashboard';
import Consumers from './pages/Consumers';
import MeterReadings from './pages/MeterReadings';
import Alerts from './pages/Alerts';
import Analytics from './pages/Analytics';
import ProtectedRoute from './components/ProtectedRoute';

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/register" element={<Register />} />
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <DashboardLayout />
          </ProtectedRoute>
        }
      >
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<Dashboard />} />
        <Route path="consumers" element={<Consumers />} />
        <Route path="readings" element={<MeterReadings />} />
        <Route path="alerts" element={<Alerts />} />
        <Route path="analytics" element={<Analytics />} />
      </Route>
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
