"use client";

import React, { useState, useEffect, useRef } from "react";

interface FilterProps {
  column: string;
  type: "text" | "number";
  activeFilters: { operator: string; value: any }[];
  onApplyFilter: (column: string, operator: string, value: any) => Promise<void>;
  onRemoveFilter: (column: string, index: number) => void;
  allData: any[];
}

const FilterComponent: React.FC<FilterProps> = ({ column, type, activeFilters, onApplyFilter, onRemoveFilter, allData }) => {
  const [filters, setFilters] = useState<{ operator: string; value: any }[]>([
    { operator: "equals", value: "" }
  ]);
  const [showFilter, setShowFilter] = useState<boolean>(false);
  const [loading, setLoading] = useState<boolean>(false);
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const [showSuggestions, setShowSuggestions] = useState<boolean>(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const operators = {
    text: ["equals", "not equals", "contains", "does not contain", "is empty"],
    number: ["equals", "not equals", "greater", "greater or equal", "less", "less or equal"]
  };

  useEffect(() => {
    setFilters(activeFilters.length > 0 ? activeFilters : [{ operator: "equals", value: "" }]);
  }, [activeFilters]);

  const updateFilter = (index: number, key: "operator" | "value", newValue: string | number) => {
    setFilters((prevFilters) => {
      const updatedFilters = [...prevFilters];
      updatedFilters[index][key] = newValue;

      if (key === "value" && type === "text") {
        handleAutocomplete(newValue as string);
      }

      return updatedFilters;
    });

    if (key === "value") {
      setTimeout(() => setShowSuggestions(false), 100); // Vorschläge ausblenden, sobald Wert gesetzt wird
    }
  };

  const handleAutocomplete = (input: string) => {
    let filteredSuggestions: string[] = [];

    const uniqueValues = [...new Set(allData.map((item) => item[column]?.toString()))];

    if (!input) {
      filteredSuggestions = uniqueValues;
    } else {
      filteredSuggestions = uniqueValues.filter((value) =>
        value && value.toLowerCase().includes(input.toLowerCase())
      );
    }

    setSuggestions(filteredSuggestions.slice(0, 5));
    setShowSuggestions(true);
  };


  const applyFilters = async () => {
    setLoading(true);
    for (const filter of filters) {
      await onApplyFilter(column, filter.operator, filter.value);
    }
    setLoading(false);
    setShowFilter(false);
    setSuggestions([]); // Close suggestions after applying filter
  };

  const resetFilters = () => {
    setFilters([{ operator: "equals", value: "" }]);
    setShowFilter(false);
    setSuggestions([]);
  };

  return (
    <div className="relative inline-block text-left">
      <button
        onClick={() => setShowFilter(!showFilter)}
        className="ml-2 p-1 rounded bg-gray-800 hover:bg-gray-600 transition text-white"
      >
        🔽
      </button>

      {showFilter && (
        <div
          ref={dropdownRef}
          className="absolute left-0 mt-2 bg-white dark:bg-gray-900 text-black dark:text-white border border-gray-300 dark:border-gray-700 shadow-lg rounded-lg w-56 p-4 z-50"
        >
          <div className="flex justify-between items-center mb-2">
            <label className="text-sm font-medium">Filter by {column}</label>
            <button onClick={resetFilters} className="text-red-500 hover:text-red-700 transition">
              ✖
            </button>
          </div>

          {filters.map((filter, index) => (
            <div key={index} className="mb-2 p-2 border rounded relative">
              <select
                value={filter.operator}
                onChange={(e) => updateFilter(index, "operator", e.target.value)}
                className="w-full p-1 border rounded bg-gray-100 dark:bg-gray-800 text-black dark:text-white"
              >
                {operators[type].map((op) => (
                  <option key={op} value={op}>
                    {op}
                  </option>
                ))}
              </select>

              <div className="relative flex items-center">
                <input
                  type={type === "number" ? "number" : "text"}
                  value={filters[index].value}
                  onChange={(e) => updateFilter(index, "value", e.target.value)}
                  className="w-full mt-2 p-1 border rounded"
                  onFocus={() => handleAutocomplete("")}  // Zeige Vorschläge an
                  onBlur={() => setTimeout(() => setShowSuggestions(false), 200)} // Verhindert sofortiges Schließen
                />

                {type === "text" && (
                  <button
                    onClick={() => handleAutocomplete("")}
                    className="ml-2 bg-gray-300 dark:bg-gray-600 px-2 py-1 rounded text-gray-800 dark:text-gray-200"
                  >
                    🔽
                  </button>
                )}
              </div>

              {showSuggestions && suggestions.length > 0 && (
                <ul className="absolute top-full left-0 w-full bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-700 mt-1 rounded shadow-lg z-50">
                  {suggestions.map((suggestion, i) => (
                    <li
                      key={i}
                      className="p-2 hover:bg-gray-200 dark:hover:bg-gray-700 cursor-pointer"
                      onMouseDown={(e) => {
                        e.preventDefault(); // Verhindert, dass das Input-Feld sofort das Blur-Event auslöst
                        updateFilter(index, "value", suggestion);
                        setSuggestions([]); // Vorschläge ausblenden
                        setShowSuggestions(false);
                      }}
                      onClick={() => setFilters([{ operator: filters[index].operator, value: suggestion }])} // Setzt den Wert im Input zurück
                    >
                      {suggestion}
                    </li>

                  ))}
                </ul>
              )}

            </div>
          ))}

          <button onClick={() => setFilters([...filters, { operator: "equals", value: "" }])}
            className="w-full bg-gray-500 hover:bg-gray-600 text-white p-1 rounded"
          >
            + Add Another Filter
          </button>

          <button
            onClick={applyFilters}
            disabled={loading}
            className={`w-full p-2 rounded-md font-semibold mt-3 transition ${loading
              ? "bg-blue-300 text-gray-700 cursor-not-allowed"
              : "bg-blue-500 hover:bg-blue-600 text-white"
              }`}
          >
            {loading ? "Applying..." : "Apply"}
          </button>
        </div>
      )}
    </div>
  );
};

export default FilterComponent;
