/**
 Copyright IBM Corporation 2016, 2017
 
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


public protocol Extension {
    
    var priority: Int { get }
    
    func buildExtension(builder: QueryBuilder) throws -> String
}

public struct AnyExtension: Extension {
   
    private var base: Any
    
    public var priority: Int {
        return (self.base as! Extension).priority
    }
    
    public init<T: Extension>(base: T) {
        self.base = base
    }
    
    public func buildExtension(builder: QueryBuilder) throws -> String {
        return try (self.base as! Extension).buildExtension(builder: builder)
    }
    
    func check<T>(for type: T.Type) -> Bool {
        return self.base is T
    }
}

struct WithExtension: Extension {
    
    public let priority = 10
    
    private let tables: [AuxiliaryTable]
    
    init(tables: [AuxiliaryTable]) {
        self.tables = tables
    }
    
    public func buildExtension(builder: QueryBuilder) throws -> String {
        let result = try "WITH " + tables.map { try $0.buildWith(queryBuilder: builder) }.joined(separator: ", ")
        
        return result
    }
}

public protocol Extendable {
    
    associatedtype Position: Hashable
    
    var extensions: [Position : [AnyExtension]] { get }
    
    func extend(with: AnyExtension, at: Position) -> Self
}

extension Extendable {
    
    func buildExtension(at position: Position, using builder: QueryBuilder) throws -> String {
        guard let extensions = self.extensions[position] else {
            return ""
        }
        
        let result = try " " + extensions.sorted { $0.priority > $1.priority }.map { try $0.buildExtension(builder: builder) }.joined(separator: " ") + " "
        return result
    }
}

// Mark: Select

/// The SQL SELECT statement.
public struct Select: Query, Extendable {
    
    //position + key
    public private (set) var extensions: [Select.Position : [AnyExtension]] = [:]
    
    public enum Position {
        case prefix
        case suffix
        case select
        case from
        case `where`
    }
    
    public func extend(with: AnyExtension, at: Position) -> Select {
        var new = self
        if new.extensions[at] == nil {
            new.extensions[at] = [with]
        } else {
            new.extensions[at]?.append(with)
        }
        return new
    }
    
    /// An array of `Field` elements to select.
    public let fields: [Field]?
    
    /// The table to select rows from.
    public let tables: [Table]

    /// The SQL WHERE clause containing the filter for rows to retrieve.
    /// Could be represented with a `Filter` clause or a `String` containing raw SQL.
    public private (set) var whereClause: QueryFilterProtocol?
    
    /// A boolean indicating whether the selected values have to be distinct.
    /// If true, corresponds to the SQL SELECT DISTINCT statement.
    public private (set) var distinct = false
    
    /// The number of rows to select.
    /// If specified, corresponds to the SQL SELECT TOP/LIMIT clause.
    public private (set) var rowsToReturn: Int?

    /// The number of rows to skip.
    /// If specified, corresponds to the SQL SELECT OFFSET clause.
    public private (set) var offset: Int?

    /// An array containing `OrderBy` elements to sort the selected rows.
    /// The SQL ORDER BY keyword.
    public private (set) var orderBy: [OrderBy]?
    
    /// An array containing `Column` elements to group the selected rows.
    /// The SQL GROUP BY statement.
    public private (set) var groupBy: [Column]?

    /// The SQL HAVING clause containing the filter for the rows to select when aggregate functions are used.
    /// Could be represented with a `Having` clause or a `String` containing raw SQL.
    public private (set) var havingClause: QueryHavingProtocol?
    
    /// The SQL UNION clauses.
    public private (set) var unions: [Union]?
    
    /// The SQL JOIN, ON and USING clauses.
    /// ON clause can be represented as `Filter` or a `String` containing raw SQL.
    /// USING clause: an array of `Column` elements that have to match in a JOIN query.
    public private (set) var joins = [(join: Join, on: QueryFilterProtocol?, using: [Column]?)]()
    
    /// An array of `AuxiliaryTable` which will be used in a query with a WITH clause.
//    public private (set) var with: [AuxiliaryTable]?

    private var syntaxError = ""

    /// Initialize an instance of Select.
    ///
    /// - Parameter fields: A list of `Field` elements to select.
    /// - Parameter from table: The table to select from.
    public init(_ fields: Field..., from table: Table) {
        self.fields = fields
        self.tables = [table]
    }
    
    /// Initialize an instance of Select.
    ///
    /// - Parameter fields: An array of `Field` elements to select.
    /// - Parameter from table: The table(s) to select from.
    public init(_ fields: [Field], from table: Table...) {
        self.fields = fields
        self.tables = table
    }

    /// Initialize an instance of Select.
    ///
    /// - Parameter fields: A list of `Field` elements to select.
    /// - Parameter from table: An array of tables to select from.
    public init(_ fields: Field..., from tables: [Table]) {
        self.fields = fields
        self.tables = tables
    }

    /// Initialize an instance of Select.
    ///
    /// - Parameter fields: An array of `Field` elements to select.
    /// - Parameter from table: An array of tables to select from.
    public init(fields: [Field], from tables: [Table]) {
        self.fields = fields
        self.tables = tables
    }

    /// Build the query using `QueryBuilder`.
    ///
    /// - Parameter queryBuilder: The QueryBuilder to use.
    /// - Returns: A String representation of the query.
    /// - Throws: QueryError.syntaxError if query build fails.
    public func build(queryBuilder: QueryBuilder) throws -> String {
        var syntaxError = self.syntaxError
        
        if groupBy == nil && havingClause != nil {
            syntaxError += "Having clause is not allowed without a group by clause. "
        }
        
        if syntaxError != "" {
            throw QueryError.syntaxError(syntaxError)
        }
        
        var select = ""
        select += "SELECT "
        
        if distinct {
            select += "DISTINCT "
        }
        
        if let fields = fields, fields.count != 0 {
            select += try "\(fields.map { try $0.build(queryBuilder: queryBuilder) }.joined(separator: ", "))"
        }
        else {
            select += "*"
        }
        
        var from = ""
        from += " FROM "
        from += try "\(tables.map { try $0.build(queryBuilder: queryBuilder) }.joined(separator: ", "))"
        
        for item in joins {
            from += try item.join.build(queryBuilder: queryBuilder)

            if let on = item.on {
                from += try " ON " + on.build(queryBuilder: queryBuilder)
            }
            
            if let using = item.using {
                from += " USING (" + using.map { $0.name }.joined(separator: ", ") + ")"
            }
        }
        
        var `where` = ""
        if let whereClause = whereClause {
            `where` += try " WHERE " + whereClause.build(queryBuilder: queryBuilder)
        }
        
        if let groupClause = groupBy {
            `where` += try " GROUP BY " + groupClause.map { try $0.build(queryBuilder: queryBuilder) }.joined(separator: ", ")
        }
        
        if let havingClause = havingClause {
            `where` += try " HAVING " + havingClause.build(queryBuilder: queryBuilder)
        }
        
        if let orderClause = orderBy {
            `where` += try " ORDER BY " + orderClause.map { try $0.build(queryBuilder: queryBuilder) }.joined(separator: ", ")
        }
        
        if let rowsToReturn = rowsToReturn {
            `where` += " LIMIT \(rowsToReturn)"
        }
        
        if let offset = offset {
            if rowsToReturn == nil {
                throw QueryError.syntaxError("Offset requires a limit to be set. ")
            }
            
            `where` += " OFFSET \(offset)"
        }
        
        if let unions = unions, unions.count != 0 {
            for union in unions {
                `where` += try union.build(queryBuilder: queryBuilder)
            }
        }
        
        let prefix = try self.buildExtension(at: .prefix, using: queryBuilder)
        let suffix = try self.buildExtension(at: .suffix, using: queryBuilder)
        let selectExtension = try self.buildExtension(at: .select, using: queryBuilder)
        let fromExtension = try self.buildExtension(at: .from, using: queryBuilder)
        let whereExtension = try self.buildExtension(at: .where, using: queryBuilder)

        var result = prefix + select + selectExtension + from + fromExtension + `where` + whereExtension + suffix
        result = updateParameterNumbers(query: result, queryBuilder: queryBuilder)
        return result
    }

    /// Create a SELECT DISTINCT query.
    ///
    /// - Parameter fields: A list of `Field`s to select.
    /// - Parameter from: The table to select from.
    /// - Returns: A new instance of Select with `distinct` flag set.
    public static func distinct(_ fields: Field..., from table: Table) -> Select {
        var selectQuery = Select(fields, from: table)
        selectQuery.distinct = true
        return selectQuery
    }
    
    /// Create a SELECT DISTINCT query.
    ///
    /// - Parameter fields: An array of `Field`s to select.
    /// - Parameter from table: The table to select from.
    /// - Returns: A new instance of Select with `distinct` flag set.
    public static func distinct(_ fields: [Field], from table: Table...) -> Select {
        var selectQuery = Select(fields: fields, from: table)
        selectQuery.distinct = true
        return selectQuery
    }
    
    /// Create a SELECT DISTINCT query.
    ///
    /// - Parameter fields: A list of `Field`s to select.
    /// - Parameter from: An array of tables to select from.
    /// - Returns: A new instance of Select with `distinct` flag set.
    public static func distinct(_ fields: Field..., from tables: [Table]) -> Select {
        var selectQuery = Select(fields: fields, from: tables)
        selectQuery.distinct = true
        return selectQuery
    }

    /// Create a SELECT DISTINCT query.
    ///
    /// - Parameter fields: An array of `Field`s to select.
    /// - Parameter from: An array of tables to select from.
    /// - Returns: A new instance of Select with `distinct` flag set.
    public static func distinct(fields: [Field], from tables: [Table]) -> Select  {
        var selectQuery = Select(fields: fields, from: tables)
        selectQuery.distinct = true
        return selectQuery
    }

    /// Add the HAVING clause to the query.
    ///
    /// - Parameter clause: The `Having` clause or a `String` containing SQL HAVING clause to apply.
    /// - Returns: A new instance of Select with the `Having` clause.
    public func having(_ clause: QueryHavingProtocol) -> Select {
        var new = self
        if havingClause != nil {
            new.syntaxError += "Multiple having clauses. "
        } else {
            new.havingClause = clause
        }
        return new
    }
    
    
    /// Add the ORDER BY keyword to the query.
    ///
    /// - Parameter by: A list of the `OrderBy` to apply.
    /// - Returns: A new instance of Select with the ORDER BY keyword.
    public func order(by clause: OrderBy...) -> Select {
        return order(by: clause)
    }
    
    /// Add the ORDER BY keyword to the query.
    ///
    /// - Parameter by: An array of the `OrderBy` to apply.
    /// - Returns: A new instance of Select with the ORDER BY keyword.
    public func order(by clause: [OrderBy]) -> Select {
        var new = self
        if orderBy != nil {
            new.syntaxError += "Multiple order by clauses. "
        }
        else {
            new.orderBy = clause
        }
        return new
    }
    
    /// Add the GROUP BY clause to the query.
    ///
    /// - Parameter by: A list of `Column`s to group by.
    /// - Returns: A new instance of Select with the GROUP BY clause.
    public func group(by clause: Column...) -> Select {
        return group(by: clause)
    }
    
    /// Add the GROUP BY clause to the query.
    ///
    /// - Parameter by: A list of `Column`s to group by.
    /// - Returns: A new instance of Select with the GROUP BY clause.
    public func group(by clause: [Column]) -> Select {
        var new = self
        if groupBy != nil {
            new.syntaxError += "Multiple group by clauses. "
        }
        else {
            new.groupBy = clause
        }
        return new
    }
    
    /// Add the LIMIT/TOP clause to the query.
    ///
    /// - Parameter to: The limit of the number of rows to select.
    /// - Returns: A new instance of Select with the LIMIT clause.
    public func limit(to newLimit: Int) -> Select {
        var new = self
        if rowsToReturn != nil {
            new.syntaxError += "Multiple limits. "
        }
        else {
            new.rowsToReturn = newLimit
        }
        return new
    }
    
    /// Add the OFFSET clause to the query.
    ///
    /// - Parameter to: The number of rows to skip.
    /// - Returns: A new instance of Select with the OFFSET clause.
    public func offset(_ offset: Int) -> Select {
        var new = self
        if new.offset != nil {
            new.syntaxError += "Multiple offsets. "
        }
        else {
            new.offset = offset
        }
        return new
    }

    
    /// Add an SQL WHERE clause to the select statement.
    ///
    /// - Parameter conditions: The `Filter` clause or a `String` containing SQL WHERE clause to apply.
    /// - Returns: A new instance of Select with the WHERE clause.
    public func `where`(_ conditions: QueryFilterProtocol) -> Select {
        var new = self
        if whereClause != nil {
            new.syntaxError += "Multiple where clauses. "
        } else {
            new.whereClause = conditions
        }
        return new
    }
    
    /// Add an SQL ON clause to the JOIN statement.
    ///
    /// - Parameter conditions: The `Filter` clause or a `String` containing SQL ON clause to apply.
    /// - Returns: A new instance of Select with the ON clause.
    public func on(_ conditions: QueryFilterProtocol) -> Select {
        var new = self
        
        guard new.joins.count > 0 else {
            new.syntaxError += "On clause set for statement that is not join. "
            return new
        }
        
        if new.joins.last?.on != nil {
            new.syntaxError += "Multiple on clauses for a single join."
        } else if new.joins.last?.using != nil {
            new.syntaxError += "An on clause is not allowed with a using clause for a single join."
        }
        else {
            new.joins[new.joins.count - 1].on = conditions
        }
        return new
    }

    
    /// Add an SQL USING clause to the JOIN statement.
    ///
    /// - Parameter columns: A list of `Column`s to match in the JOIN statement.
    /// - Returns: A new instance of Select with the USING clause.
    public func using(_ columns: Column...) -> Select {
        return using(columns)
    }
    
    /// Add an SQL USING clause to the JOIN statement.
    ///
    /// - Parameter columns: An array of `Column`s to match in the JOIN statement.
    /// - Returns: A new instance of Select with the USING clause.
    public func using(_ columns: [Column]) -> Select {
        var new = self
        
        guard new.joins.count > 0 else {
            new.syntaxError += "Using clause set for statement that is not join. "
            return new
        }
        
        if new.joins.last?.using != nil {
            new.syntaxError += "Multiple using clauses for a single join."
        } else if new.joins.last?.on != nil {
            new.syntaxError += "A using clause is not allowed with an on clause for single join."
        }
        else {
            new.joins[new.joins.count - 1].using = columns
        }
        return new
    }
    
    /// Create an SQL SELECT UNION statement.
    ///
    /// - Parameter table: The second Select query used in performing the union. 
    /// - Returns: A new instance of Select corresponding to the SELECT UNION.
    public func union(_ query: Select) -> Select {
        var new = self
        if unions == nil {
            new.unions = [Union]()
        }
        new.unions!.append(.union(query))
        return new
    }

    /// Create an SQL SELECT UNION ALL statement.
    ///
    /// - Parameter table: The second Select query used in performing the union.
    /// - Returns: A new instance of Select corresponding to the SELECT UNION ALL.
    public func unionAll(_ query: Select) -> Select {
        var new = self
        if unions == nil {
            new.unions = [Union]()
        }
        new.unions!.append(.unionAll(query))
        return new
    }
    
    /// Create an SQL SELECT INNER JOIN statement.
    ///
    /// - Parameter table: The right table used in performing the join. The left table is the table field of this `Select` instance.
    /// - Returns: A new instance of Select corresponding to the SELECT INNER JOIN.
    public func join(_ table: Table) -> Select {
        var new = self
        new.joins.append((.join(table), nil, nil))
        return new
    }
    
    /// Create an SQL SELECT LEFT JOIN statement.
    ///
    /// - Parameter table: The right table used in performing the join. The left table is the table field of this `Select` instance.
    /// - Returns: A new instance of Select corresponding to the SELECT LEFT JOIN.
    public func leftJoin(_ table: Table) -> Select {
        var new = self
        new.joins.append((.left(table), nil, nil))
        return new
    }
    
    /// Create an SQL SELECT CROSS JOIN statement.
    ///
    /// - Parameter table: The right table used in performing the join. The left table is the table field of this `Select` instance.
    /// - Returns: A new instance of Select corresponding to the SELECT CROSS JOIN.
    public func crossJoin(_ table: Table) -> Select {
        var new = self
        new.joins.append((.cross(table), nil, nil))
        return new
    }
    
    /// Create an SQL SELECT NATURAL JOIN statement.
    ///
    /// - Parameter table: The right table used in performing the join. The left table is the table field of this `Select` instance.
    /// - Returns: A new instance of Select corresponding to the SELECT NATURAL JOIN.
    public func naturalJoin(_ table: Table) -> Select {
        var new = self
        new.joins.append((.natural(table), nil, nil))
        return new
    }

    /// Create a join statement with the type of join specified in the String.
    ///
    /// - Parameter raw: A String containg a join to apply.
    /// - Parameter table: The right table used in performing the join. The left table is the table field of this `Select` instance.
    /// - Returns: A new instance of Select corresponding to the join.
    public func rawJoin(_ raw: String, _ table: Table) -> Select {
        var new = self
        new.joins.append((.raw(raw, table), nil, nil))
        return new
    }
    
    /// Set tables to be used for WITH clause.
    ///
    /// - Parameter tables: A list of the `AuxiliaryTable` to apply.
    /// - Returns: A new instance of Select with tables for WITH clause.
    func with(_ tables: [AuxiliaryTable]) -> Select {
        var new = self
        if let extensions = new.extensions[.prefix],
            (extensions.filter { $0.check(for: WithExtension.self) }).count > 0 {
            new.syntaxError += "Multiple with clauses. "
            return new
        } else {
            let `extension` = AnyExtension(base: WithExtension(tables: tables))
            return new.extend(with: `extension`, at: .prefix)
        }
    }
}
