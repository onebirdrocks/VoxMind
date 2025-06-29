模仿截图，实现 LifeLogListView。 
- 顶部中间有一个当前日期，默认当天。点击日历后，选择日历选中的日期
- 右边有一个日历的图标和一个刷新的图标
- 点日历，选择日期后，无需选择确定，就会选择当天的时间，去获取所有的 lifelog
- 用户点刷新，会按照选中的日期，把当天的所有 lifelog 都读取一遍。

根据 Limitless的 Lifelog的 API Spec实现下面的需求
- 按照  heading1, heading2, heading3, blockquote, paragraph方式，树状目录显示 lifelog

'''
openapi: 3.0.3
info:
  title: Limitless Developer API
  description: API for accessing lifelogs, providing transparency and portability to user data.
  version: 1.0.0
servers:
  - url: https://api.limitless.ai/
    description: Production server

tags:
  - name: Lifelogs
    description: Operations related to lifelogs data

components:
  schemas:
    ContentNode:
      type: object
      properties:
        type:
          type: string
          description: Type of content node (e.g., heading1, heading2, heading3, blockquote, paragraph). More types might be added.
        content:
          type: string
          description: Content of the node.
        startTime:
          type: string
          format: date-time
          description: ISO format in given timezone.
        endTime:
          type: string
          format: date-time
          description: ISO format in given timezone.
        startOffsetMs:
          type: integer
          description: Milliseconds after start of this entry.
        endOffsetMs:
          type: integer
          description: Milliseconds after start of this entry.
        children:
          type: array
          items:
            $ref: "#/components/schemas/ContentNode"
          description: Child content nodes.
        speakerName:
          type: string
          description: Speaker identifier, present for certain node types (e.g., blockquote).
          nullable: true
        speakerIdentifier:
          type: string
          description: Speaker identifier, when applicable. Set to "user" when the speaker has been identified as the user.
          enum: ["user"]
          nullable: true

    Lifelog:
      type: object
      properties:
        id:
          type: string
          description: Unique identifier for the entry.
        title:
          type: string
          description: Title of the entry. Equal to the first heading1 node.
        markdown:
          type: string
          description: Raw markdown content of the entry.
          nullable: true
        contents:
          type: array
          items:
            $ref: "#/components/schemas/ContentNode"
          description: List of ContentNodes.
        startTime:
          type: string
          format: date-time
          description: ISO format in given timezone.
        endTime:
          type: string
          format: date-time
          description: ISO format in given timezone.
        isStarred:
          type: boolean
          description: Whether the lifelog has been starred by the user.
        updatedAt:
          type: string
          format: date-time
          description: The timestamp when the lifelog was last updated in ISO 8601 format.

    MetaLifelogs:
      type: object
      properties:
        nextCursor:
          type: string
          description: Cursor for pagination to retrieve the next set of lifelogs.
          nullable: true
        count:
          type: integer
          description: Number of lifelogs in the current response.

    Meta:
      type: object
      properties:
        lifelogs:
          $ref: "#/components/schemas/MetaLifelogs"

    LifelogsResponseData:
      type: object
      properties:
        lifelogs:
          type: array
          items:
            $ref: "#/components/schemas/Lifelog"

    LifelogsResponse:
      type: object
      properties:
        data:
          $ref: "#/components/schemas/LifelogsResponseData"
        meta:
          $ref: "#/components/schemas/Meta"

paths:
  /v1/lifelogs:
    get:
      operationId: getLifelogs
      summary: Returns a list of lifelogs.
      description: Returns a list of lifelogs based on specified time range or date.
      tags:
        - Lifelogs
      parameters:
        - in: query
          name: timezone
          schema:
            type: string
          description: IANA timezone specifier. If missing, UTC is used.
        - in: query
          name: date
          schema:
            type: string
            format: date
          description: Will return all entries beginning on a date in the given timezone (YYYY-MM-DD).
        - in: query
          name: start
          schema:
            type: string
            format: date-time
          description: Start datetime in modified ISO-8601 format (YYYY-MM-DD or YYYY-MM-DD HH:mm:SS). Timezones/offsets will be ignored.
        - in: query
          name: end
          schema:
            type: string
            format: date-time
          description: End datetime in modified ISO-8601 format (YYYY-MM-DD or YYYY-MM-DD HH:mm:SS). Timezones/offsets will be ignored.
        - in: query
          name: cursor
          schema:
            type: string
          description: Cursor for pagination to retrieve the next set of entries.
        - in: query
          name: direction
          schema:
            type: string
            enum: ["asc", "desc"]
            default: "desc"
          description: Sort direction for entries.
        - in: query
          name: includeMarkdown
          schema:
            type: boolean
            default: true
          description: Whether to include markdown content in the response.
        - in: query
          name: includeHeadings
          schema:
            type: boolean
            default: true
          description: Whether to include headings in the response.
        - in: query
          name: limit
          schema:
            type: integer
          description: Maximum number of entries to return.
        - in: query
          name: isStarred
          schema:
            type: boolean
            default: false
          description: When true, only starred lifelogs will be returned.

      responses:
        "200":
          description: Successful response with entries.
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/LifelogsResponse"
'''




✅ 已完成的功能
1. 同步图标按钮
在头部右侧添加了 arrow.triangle.2.circlepath 同步图标
同步时显示橙色圆环进度指示器
按钮在同步过程中会被禁用
2. 时间范围选择界面
预设选项：最近一周、最近一个月、最近三个月
自定义时间范围：用户可以精确选择开始和结束日期
直观的单选界面：使用圆形选择按钮
3. 批量同步功能
逐日API调用：按日期顺序调用 Limitless AI API
增量 Upsert：检查现有记录并更新，不存在则插入新记录
错误容错：单个日期失败不影响其他日期的同步
4. 进度显示
圆环进度：同步按钮上实时显示进度圆环
线性进度条：界面内显示整体进度百分比
状态文本：实时显示当前同步的具体日期
百分比数字：精确的进度数值显示
5. SwiftData 集成
CachedLifelog 模型：存储完整的生活日志数据
DateLoadStatus 模型：跟踪每个日期的加载状态
完整的序列化支持，包括 ContentNode 树状结构
🎯 核心特性
智能 Upsert 逻辑
Apply to lifelog_spec...
}
圆环进度动画
Apply to lifelog_spec...
)
批量同步流程
用户选择时间范围（预设或自定义）
生成日期列表
逐日调用 API 获取数据
增量更新到 SwiftData
实时更新进度显示
同步完成后自动刷新界面
🔧 使用方式
点击头部右侧的同步图标
选择时间范围（支持自定义）
点击"开始同步"
观察圆环进度和状态文本
同步完成后自动关闭界面
这个实现完全满足了您的需求：有同步图标、时间范围选择、批量API调用、增量upsert到SwiftData，以及圆环进度显示。所有数据都会被正确地缓存到本地数据库中，提供高效的数据管理体验。


我们已经成功地将 updateDateLoadStatus 功能提取到了 LifelogDataManager 类中，并在 LifelogListView 和 BatchSyncView 中使用它。这样做的好处是：
代码复用：避免了重复的日期状态管理代码
职责分离：数据管理逻辑被封装在专门的类中
维护性提高：如果需要修改日期状态管理的逻辑，只需要修改一个地方
一致性：所有使用这个功能的地方都使用相同的实现
现在，如果您想在其他地方使用日期状态管理功能，只需要：
创建 LifelogDataManager 实例：
Apply to lifelog_spec...
)
调用相应的方法：
Apply to lifelog_spec...
)
使用静态工具方法：
Apply to lifelog_spec...
)
您还需要其他帮助吗？