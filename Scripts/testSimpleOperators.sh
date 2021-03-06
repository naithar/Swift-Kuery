#!/bin/bash

#/**
#* Copyright IBM Corporation 2016
#*
#* Licensed under the Apache License, Version 2.0 (the "License");
#* you may not use this file except in compliance with the License.
#* You may obtain a copy of the License at
#*
#* http://www.apache.org/licenses/LICENSE-2.0
#*
#* Unless required by applicable law or agreed to in writing, software
#* distributed under the License is distributed on an "AS IS" BASIS,
#* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#* See the License for the specific language governing permissions and
#* limitations under the License.
#**/

SCRIPT_DIR=$(dirname "$BASH_SOURCE")
cd "$SCRIPT_DIR"
CUR_DIR=$(pwd)

temp=$(dirname "${CUR_DIR}")
temp=$(dirname "${temp}")
PKG_DIR=$(dirname "${CUR_DIR}")

shopt -s nullglob

if ! [ -d "${PKG_DIR}/Tests/SwiftKueryTests" ]; then
echo "Failed to find ${PKG_DIR}/Tests/SwiftKueryTests"
exit 1
fi

INPUT_OPERATORS_FILE="${PKG_DIR}/Scripts/SimpleOperators.txt"
INPUT_TYPES_FILE="${PKG_DIR}/Scripts/FilterAndHavingTypes.txt"

INPUT_BOOL_OPERATORS_FILE="${PKG_DIR}/Scripts/FilterAndHavingBoolOperators.txt"
INPUT_BOOL_TYPES_FILE="${PKG_DIR}/Scripts/FilterAndHavingBoolTypes.txt"

OUTPUT_FILE="${PKG_DIR}/Tests/SwiftKueryTests/TestFilterAndHaving.swift"

echo "--- Generating ${OUTPUT_FILE}"

cat <<'EOF' > ${OUTPUT_FILE}
/**
* Copyright IBM Corporation 2016
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
**/

import XCTest

@testable import SwiftKuery

// This test was generated by Scripts/testSimpleOperators.sh.
class TestFilterAndHaving: XCTestCase {

    static var allTests: [(String, (TestFilterAndHaving) -> () throws -> Void)] {
        return [
            ("testSimpleOperators", testSimpleOperators),
        ]
    }

    class MyTable: Table {
        let a = Column("a")
        let b = Column("b")

        let tableName = "table"
    }

    class MyTable2: Table {
        let c = Column("c")
        let tableName = "table2"
    }

    func testSimpleOperators() {
        let t = MyTable()
        let t2 = MyTable2()
        let connection = createConnection()
        var s = Select(from: t)
        var kuery = ""
        var queryWhere = ""
        var queryHaving = ""

EOF


# Generate test for operators for simple conditions that return Filter and Having

for INPUT_TYPES in $INPUT_TYPES_FILE $INPUT_BOOL_TYPES_FILE; do
    if [[ $INPUT_TYPES == *"Bool"* ]]
    then
        INPUT_OPERATORS=$INPUT_BOOL_OPERATORS_FILE
    else
        INPUT_OPERATORS=$INPUT_OPERATORS_FILE
    fi


while read -r LINE; do
    [ -z "$LINE" ] && continue
    [[ "$LINE" =~ ^#.*$ ]] && continue
    stringarray=($LINE)
    OPERATOR=${stringarray[0]}
    SQL_OPERATOR=${stringarray[2]}
    while read -r LINE; do
        [ -z "$LINE" ] && continue
        [[ "$LINE" =~ ^#.*$ ]] && continue
        stringarray=($LINE)
        CLAUSE=${stringarray[3]}
        OPERAND1=${stringarray[4]}
        OPERAND2=${stringarray[5]}
        SQL_OPERAND1=${stringarray[6]}
        SQL_OPERAND2=${stringarray[7]}

        CLAUSE_UPPER="$(tr '[:lower:]' '[:upper:]' <<< $CLAUSE)"
        # Remove backslashes.
        SQL_OPERAND1=${SQL_OPERAND1/\\}
        SQL_OPERAND2=${SQL_OPERAND2/\\}
        # Replace underscores with whitespaces.
        OPERAND1=${OPERAND1//_/" "}
        OPERAND2=${OPERAND2//_/" "}
        SQL_OPERAND1=${SQL_OPERAND1//_/" "}
        SQL_OPERAND2=${SQL_OPERAND2//_/" "}

cat <<EOF >> ${OUTPUT_FILE}

        s = Select(t.a, from: t)
            .group(by: t.a)
            .$CLAUSE($OPERAND1 $OPERATOR $OPERAND2)
        kuery = connection.descriptionOf(query: s)
        queryWhere = "SELECT table.a FROM table $CLAUSE_UPPER $SQL_OPERAND1 $SQL_OPERATOR $SQL_OPERAND2 GROUP BY table.a"
        queryHaving = "SELECT table.a FROM table GROUP BY table.a $CLAUSE_UPPER $SQL_OPERAND1 $SQL_OPERATOR $SQL_OPERAND2"
        XCTAssert(kuery == queryWhere || kuery == queryHaving,
                    "\nError in query construction: \n\(kuery) \ninstead of \n\(queryWhere) \nor instead of \n\(queryHaving)")
EOF

    done < $INPUT_TYPES
done < $INPUT_OPERATORS

done

echo "  }" >> ${OUTPUT_FILE}
echo "}" >> ${OUTPUT_FILE}
