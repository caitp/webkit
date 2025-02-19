/*
 * Copyright (C) 2022 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#pragma once

#include "CSSValue.h"
#include "CSSValueKeywords.h"
#include <wtf/text/AtomString.h>

namespace WebCore::MQ {

enum class LogicalOperator : uint8_t { And, Or, Not };
enum class ComparisonOperator : uint8_t { LessThan, LessThanOrEqual, Equal, GreaterThan, GreaterThanOrEqual };
enum class Syntax : uint8_t { Boolean, Plain, Range };

struct Condition;
struct FeatureSchema;

struct Comparison {
    ComparisonOperator op;
    RefPtr<CSSValue> value;
};

struct Feature {
    AtomString name;
    Syntax syntax;
    std::optional<Comparison> leftComparison;
    std::optional<Comparison> rightComparison;

    const FeatureSchema* validSchema { nullptr };
};

struct GeneralEnclosed {
    String name;
    String text;
};

using QueryInParens = std::variant<Condition, Feature, GeneralEnclosed>;

struct Condition {
    LogicalOperator logicalOperator { LogicalOperator::And };
    Vector<QueryInParens> queries;
};

struct FeatureSchema {
    enum class Type : uint8_t { Discrete, Range };
    enum class ValueType : uint8_t {
        Integer =       1 << 0,
        Number =        1 << 1,
        Length =        1 << 2,
        Ratio =         1 << 3,
        Resolution =    1 << 4,
    };

    AtomString name;
    Type type;
    OptionSet<ValueType> valueTypes;
    Vector<CSSValueID> valueIdentifiers;
};

}
