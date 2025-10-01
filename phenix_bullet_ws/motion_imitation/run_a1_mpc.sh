#!/bin/bash
echo "Запуск MPC симуляции для Unitree A1..."
cd /phenix_bullet_ws/motion_imitation
python3 mpc_controller/locomotion_controller_example.py
