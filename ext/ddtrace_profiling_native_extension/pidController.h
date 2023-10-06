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

// Originally imported from https://github.com/DataDog/java-profiler/blob/11fe6206c31a14c6e5134e8401eaec8b22c618d7/ddprof-lib/src/main/cpp/pidController.h

#ifndef _PIDCONTROLLER_H
#define _PIDCONTROLLER_H

#include <cmath>
#include "arch.h"

/*
 * A simple implementation of a PID controller.
 * Heavily influenced by https://tttapa.github.io/Pages/Arduino/Control-Theory/Motor-Fader/PID-Cpp-Implementation.html 
 */
class PidController {
    private:
        u64 _target;
        double _proportional_gain;
        double _derivative_gain;
        double _integral_gain;
        double _alpha;

        double _avg_error;
        long long _integral_value;

        inline static double computeAlpha(float cutoff) {
            if (cutoff <= 0)
                return 1;
            // α(fₙ) = cos(2πfₙ) - 1 + √( cos(2πfₙ)² - 4 cos(2πfₙ) + 3 )
            const double c = std::cos(2 * double(M_PI) * cutoff);
            return c - 1 + std::sqrt(c * c - 4 * c + 3);
        }

    public:
        PidController(u64 target_per_second, double proportional_gain, double integral_gain, double derivative_gain, int sampling_window, double cutoff_secs) : 
            _target(target_per_second * sampling_window), 
            _proportional_gain(proportional_gain), 
            _integral_gain(integral_gain * sampling_window), 
            _derivative_gain(derivative_gain / sampling_window),
            _alpha(computeAlpha(sampling_window / cutoff_secs)),
            _avg_error(0),
            _integral_value(0) {}
        
        double compute(u64 input, double time_delta_seconds);
};


#endif
