/**
 Copyright IBM Corporation 2016
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

// MARK: Column

/// Definition of table column.
public class Column: Field, Creatable {
    /// The name of the column.
    public private (set) var name: String
    
    /// The alias of the column.
    public var alias: String?
    
    /// The table to which the column belongs.
    public weak var table: Table!
    
    private var columnType: SQLDataType.Type?
    private var options = [ColumnOptions]()
    

    /// Initialize an instance of Column.
    ///
    /// - Parameter name: The name of the column.
    public init(_ name: String, type: SQLDataType.Type? = nil, options: [ColumnOptions] = []) {
        self.name = name
        self.columnType = type
        self.options = options
    }
    
    /// Build the column using `QueryBuilder`.
    ///
    /// - Parameter queryBuilder: The QueryBuilder to use.
    /// - Returns: A String representation of the column.
    /// - Throws: QueryError.syntaxError if query build fails.
    public func build(queryBuilder: QueryBuilder) throws -> String {
        let tableName = table.nameInQuery
        if tableName == "" {
            throw QueryError.syntaxError("Table name not set. ")
        }
        var result = tableName + "." + packName(name)
        if let alias = alias {
            result += " AS " + packName(alias)
        }
        return result
    }
    
    public func create() throws -> String {
        guard let type = columnType else {
            throw QueryError.databaseError("Column type not set.")
        }
        
        return name + " " + type.sqlName
    }

    /// Add an alias to the column, i.e., implement the SQL AS operator.
    ///
    /// - Parameter newName: A String containing the alias for the column.
    /// - Returns: A new Column instance with the alias.
    public func `as`(_ newName: String) -> Column {
        let new = Column(name)
        new.alias = newName
        new.table = table
        return new
    }
}

