/***************************************************************************//**
 *   @file   another_file.h
 *   @brief  Header file of another_file.
 *   @author Cristian Pop (cristian.pop@analog.com)
********************************************************************************
 * Copyright 2021(c) Analog Devices, Inc.
 *
 * SPDX-License-Identifier: BSD-3-Clause
*******************************************************************************/

#ifndef ANOTHER_FILE5_H_
#define ANOTHER_FILE5_H_

#include <stdint.h>
#include <stdbool.h>
#include "ad9083.h"

#ifdef TEST1
// OK
#endif

#ifdef TEST2
// OK
#endif

#ifdef TEST3
// OK
#endif

#ifdef TEST4
// OK
#endif

#ifdef TEST5
#ifdef TEST6
#ifdef TEST7
#endif
#endif
// NOK

#endif
