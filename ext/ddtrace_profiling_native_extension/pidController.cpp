/*
 * Copyright 2023 Datadog, Inc
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Originally imported from https://github.com/DataDog/java-profiler/blob/11fe6206c31a14c6e5134e8401eaec8b22c618d7/ddprof-lib/src/main/cpp/pidController.cpp

#include "pidController.h"

double PidController::compute(u64 input, double time_delta_coefficient) {
    // time_delta_coefficient allows variable sampling window
    // the values are linearly scaled using that coefficient to reinterpret the given value within the expected sampling window
    double absolute_error = (static_cast<double>(_target) - static_cast<double>(input)) * time_delta_coefficient;

    double avg_error = (_alpha * absolute_error) + ((1 - _alpha) * _avg_error);
    double derivative = avg_error - _avg_error;

    // PID formula:
    // u[k] = Kp e[k] + Ki e_i[k] + Kd e_d[k], control signal
    double signal = _proportional_gain * absolute_error + _integral_gain * _integral_value + _derivative_gain * derivative;

    _integral_value += absolute_error;
    _avg_error = avg_error;

    return signal;
}
